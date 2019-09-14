from __future__ import division
import ldap
import re
import json
from elasticsearch import Elasticsearch, RequestsHttpConnection
from elasticsearch.exceptions import NotFoundError as NotFoundError
from requests_aws4auth import AWS4Auth
import pytz
import ast
import boto3
import logging
import sys
import urllib3
import os
import datetime


def get_aligo_configuration():
    '''
    Return general configuration parameter
    '''
    secretsmanager_client = boto3.client('secretsmanager')
    configuration_secret_name = os.environ['SOCA_CONFIGURATION']
    response = secretsmanager_client.get_secret_value(SecretId=configuration_secret_name)
    return json.loads(response['SecretString'])


def get_aws_pricing(ec2_instance_type):
    pricing = {}
    response = client.get_products(
        ServiceCode='AmazonEC2',
        Filters=[
            {
                'Type': 'TERM_MATCH',
                'Field': 'usageType',
                'Value': 'USW2-BoxUsage:' + ec2_instance_type
            },
        ],

    )
    for data in response['PriceList']:
        data = ast.literal_eval(data)
        for k, v in data['terms'].items():
            if k == 'OnDemand':
                for skus in v.keys():
                    for ratecode in v[skus]['priceDimensions'].keys():
                        instance_data = v[skus]['priceDimensions'][ratecode]
                        if 'on demand linux ' + str(ec2_instance_type) + ' instance hour' in instance_data['description'].lower():
                            pricing['ondemand'] = float(instance_data['pricePerUnit']['USD'])
            else:
                for skus in v.keys():
                    if v[skus]['termAttributes']['OfferingClass'] == 'standard' \
                            and v[skus]['termAttributes']['LeaseContractLength'] == '1yr' \
                            and v[skus]['termAttributes']['PurchaseOption'] == 'No Upfront':
                        for ratecode in v[skus]['priceDimensions'].keys():
                            instance_data = v[skus]['priceDimensions'][ratecode]
                            if 'Linux/UNIX (Amazon VPC)' in instance_data['description']:
                                pricing['reserved'] = float(instance_data['pricePerUnit']['USD'])


    return pricing


def es_entry_exist(job_id):
    json_to_push = {
        "query": {
                "bool": {
                    "must": [
                        {"match": {"job_id": job_id}}
                    ],
                },
            },
    }
    try:
        response = es.search(index="jobs",
                         scroll='2m',
                         size=1000,
                         body=json_to_push)
    except NotFoundError:
        print("First entry, Index doest not exist but will be created automaticall.y")
        return False

    sid = response['_scroll_id']
    scroll_size = response['hits']['total']
    existing_entries = []

    while scroll_size > 0:
        data = [doc for doc in response['hits']['hits']]

        for key in data:
            existing_entries.append(key["_source"])

        response = es.scroll(scroll_id=sid, scroll='2m')
        sid = response['_scroll_id']
        scroll_size = len(response['hits']['hits'])

    if existing_entries.__len__() == 0:
        return False
    else:
        return True


def es_index_new_item(body):
    index = "jobs"
    doc_type = "item"
    add = es.index(index=index,
                   doc_type=doc_type,
                   body=body)

    if add['result'] == 'created':
        return True
    else:
        return False


def read_file(filename):
    print('Opening ' +filename)
    try:
        log_file = open(filename, 'r')
        content = log_file.read()
        log_file.close()
    except:
        # handle case were file does not exist
        content = ''
    return content


if __name__ == "__main__":


    urllib3.disable_warnings()
    aligo_configuration = get_aligo_configuration()

    # Pricing API is only available us-east-1
    client = boto3.client('pricing', region_name='us-east-1')
    accounting_log_path='/var/spool/pbs/server_priv/accounting/'
    # Change PyTZ as needed
    tz = pytz.timezone('America/Los_Angeles')
    session = boto3.Session()
    credentials = session.get_credentials()
    awsauth = AWS4Auth(credentials.access_key, credentials.secret_key, session.region_name, 'es', session_token=credentials.token)
    es_endpoint = 'https://' + aligo_configuration['ESDomainEndpoint']
    es = Elasticsearch([es_endpoint], port=443,
                       http_auth=awsauth,
                       use_ssl=True,
                       verify_certs=True,
                       connection_class=RequestsHttpConnection)

    pricing_table = {}
    management_chain_per_user = {}
    json_output = []
    output = {}

    # days_to_check = 1 --> Check today & yesterday logs. You can adjust this as needed
    days_to_check = 1
    date_to_check = [(datetime.datetime.now() - datetime.timedelta(days_to_check)).strftime('%Y%m%d'),
                     datetime.datetime.now().strftime('%Y%m%d')]
    for day in date_to_check:
        response = read_file(accounting_log_path+day)
        try:
            for line in response.splitlines():
                try:
                    data = (line.rstrip()).split(';')
                    if data.__len__() != 4:
                        pass
                    else:
                        timestamp = data[0]
                        job_state = data[1]
                        job_id = data[2].split('.')[0]
                        job_data = data[3]
                        if job_id in output.keys():
                            output[job_id].append({'utc_date': timestamp,
                                                   'job_state': job_state,
                                                   'job_id': job_id,
                                                   'job_data': job_data
                                                   })


                        else:
                            output[job_id] = [{'utc_date': timestamp,
                                               'job_state': job_state,
                                               'job_id': job_id,
                                               'job_data': job_data
                                               }]
                except Exception as e:
                    exc_type, exc_obj, exc_tb = sys.exc_info()
                    fname = os.path.split(exc_tb.tb_frame.f_code.co_filename)[1]
                    print (exc_type, fname, exc_tb.tb_lineno, line)
                    exit(1)

        except Exception as e:
            exc_type, exc_obj, exc_tb = sys.exc_info()
            fname = os.path.split(exc_tb.tb_frame.f_code.co_filename)[1]
            print (exc_type, fname, exc_tb.tb_lineno, line)
            exit(1)
            # logger.error('Error while parsing logs ' + pbs_accounting_log_date + ' : ' + str((exc_type, fname, exc_tb.tb_lineno)))

    for job_id, values in output.items():
        try:
            for data in values:
                try:
                    if data['job_state'].lower() == 'e':
                        ignore = False
                        if 'resources_used.instance_type_used' not in data['job_data']:
                            # job not done
                            ignore = True
                        else:
                            queue = re.search(r'queue=(\w+)', data['job_data']).group(1)
                            if queue in ['desktop2d', 'desktop3d']:
                                ignore = True

                        if ignore is False:
                            used_resources = re.findall('(\w+)=([^\s]+)', data['job_data'])

                            if used_resources:
                                tmp = {'job_id': job_id}
                                for res in used_resources:
                                    resource_name = res[0]
                                    resource_value = res[1]
                                    if resource_name == 'instance_type_used':
                                        resource_value = resource_value.replace('_', '.')

                                    if resource_name == 'select':
                                        mpiprocs = re.search(r'mpiprocs=(\d+)', resource_value)
                                        if mpiprocs:
                                            tmp['mpiprocs'] = int(re.search(r'mpiprocs=(\d+)', resource_value).group(1))

                                    if 'ppn' in resource_value:
                                        ppn = re.search(r'ppn=(\d+)', resource_value)
                                        if ppn:
                                            tmp['ppn'] = int(re.search(r'ppn=(\d+)', resource_value).group(1))

                                    tmp[resource_name] = int(resource_value) if resource_value.isdigit() is True else resource_value

                                # Adding custom field to index
                                tmp['simulation_time_seconds'] = tmp['end'] - tmp['start']
                                tmp['simulation_time_minutes'] = float(tmp['simulation_time_seconds'] / 60)
                                tmp['simulation_time_hours'] = float(tmp['simulation_time_minutes'] / 60)
                                tmp['simulation_time_days'] = float(tmp['simulation_time_hours'] / 24)

                                tmp['mem_kb'] = int(tmp['mem'].replace('kb', ''))
                                tmp['vmem_kb'] = int(tmp['vmem'].replace('kb', ''))

                                tmp['qtime_iso'] = (datetime.datetime.fromtimestamp(tmp['qtime'], tz).isoformat())
                                tmp['etime_iso'] = (datetime.datetime.fromtimestamp(tmp['etime'], tz).isoformat())
                                tmp['ctime_iso'] = (datetime.datetime.fromtimestamp(tmp['ctime'], tz).isoformat())
                                tmp['start_iso'] = (datetime.datetime.fromtimestamp(tmp['start'], tz).isoformat())
                                tmp['end_iso'] = (datetime.datetime.fromtimestamp(tmp['end'], tz).isoformat())

                                if tmp['instance_type_used'] not in pricing_table.keys():
                                    pricing_table[tmp['instance_type_used']] = get_aws_pricing(tmp['instance_type_used'])

                                tmp['price_ondemand'] = (tmp['simulation_time_hours'] * pricing_table[tmp['instance_type_used']]['ondemand']) * tmp['nodect']
                                tmp['price_reserved'] = (tmp['simulation_time_hours'] * pricing_table[tmp['instance_type_used']]['reserved']) * tmp['nodect']


                            json_output.append(tmp)
                except Exception as e:
                    print("===========")
                    exc_type, exc_obj, exc_tb = sys.exc_info()
                    fname = os.path.split(exc_tb.tb_frame.f_code.co_filename)[1]
                    print('Error with ' + str(data))
                    print ((exc_type, fname, exc_tb.tb_lineno))
                    print('Job id: ' + str(job_id))
                    print("===========")
                    exit(1)


        except Exception as e:
            exc_type, exc_obj, exc_tb = sys.exc_info()
            fname = os.path.split(exc_tb.tb_frame.f_code.co_filename)[1]
            print('Error')
            print ((exc_type, fname, exc_tb.tb_lineno))
            #print e
            #print "Entry error:"
            #print str(data)
            #logger.error('Error while indexing job  ' + str(output[job_id]) + ' : ' + str((exc_type, fname, exc_tb.tb_lineno)))
            exit(1)

    for entry in json_output:
        if es_entry_exist(entry['job_id']) is False:
            if es_index_new_item(json.dumps(entry)) is False:
                print('Error while indexing ' + str(entry))
                exit(1)
            else:
                print('Indexed '+str(entry))

        else:
            #print 'Already Indexed' + str(entry)
            pass

