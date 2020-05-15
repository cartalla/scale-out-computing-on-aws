import logging
import config
from decorators import login_required
from flask import render_template, request, redirect, session, flash, Blueprint
from cryptography.fernet import Fernet, InvalidToken, InvalidSignature
import json
import base64
from requests import post
from views.my_files import decrypt, user_has_permission
from models import ApplicationProfiles
from collections import OrderedDict
import re

logger = logging.getLogger(__name__)
submit_job = Blueprint('submit_job', __name__, template_folder='templates')



@submit_job.route('/submit_job', methods=['GET'])
@login_required
def index():
    app = request.args.get("app", None)
    input_file = request.args.get("input_file", None)
    if input_file is None or input_file == "":
        # User must specify input first
        flash("What input file do you want to use? <hr> Navigate to the folder where your input file is located then click 'Use as Simulation Input' icon: <i class='fas fa-microchip fa-lg'  style='color: grey'></i>","info")
        return redirect("/my_files")

    if app is None:
        application_profiles = {}
        get_all_application_profiles = ApplicationProfiles.query.all()
        for profile in get_all_application_profiles:
            application_profiles[profile.id] = {"profile_name": profile.profile_name,
                                                "profile_thumbnail": profile.profile_thumbnail}

        return render_template('submit_job.html',
                               user=session["user"],
                               application_profiles=OrderedDict(sorted(application_profiles.items(), key=lambda x: x[1]['profile_name'].lower())),
                               input_file=False if input_file is None else input_file)
    else:
        # input and app specified
        input_file_info = request.args.get('input_file')
        get_application_profile = ApplicationProfiles.query.filter_by(id=app).first()
        if get_application_profile:
            profile_form = base64.b64decode(get_application_profile.profile_form)
            profile_job = get_application_profile.profile_job
            return render_template('submit_job_selected_application.html',
                                   user=session["user"],
                                   profile_form=profile_form,
                                   profile_job=profile_job)
        else:
            flash("Application not found.", "error")
            return redirect("/submit_job")


@submit_job.route('/submit_job', methods=['POST'])
@login_required
def job_submission():
    if "app" not in request.form or "input_file" not in request.form:
        flash("Missing required parameters.", "error")
        return redirect("/submit_job")

    app = request.form["app"]
    input_file_info = request.form['input_file']
    get_application_profile = ApplicationProfiles.query.filter_by(id=app).first()
    if get_application_profile:
        file_info = decrypt(input_file_info)
        if file_info["success"] != True:
            flash("Unable to use this file as an input (maybe the file was removed or you do not have permission to access it. <br> Please try again or use a different model. Error is: " + str(file_info), "error")
            return redirect("/submit_job")
        profile_form = base64.b64decode(get_application_profile.profile_form).decode()


        profile_job = get_application_profile.profile_job

        input_path = json.loads(file_info["message"])["file_path"]
        input_name = input_path.split("/")[-1]

        return render_template('submit_job_selected_application.html',
                                   profile_name=get_application_profile.profile_name,
                                   user=session["user"],
                                   profile_form=profile_form,
                                   profile_job=profile_job,
                                   input_path=input_path.rstrip().lstrip(),
                                   input_name=input_name)
                                   #get_all_ec2_instances=get_all_ec2_instances)
    else:
        flash("Application not found.", "error")
        return redirect("/submit_job")


@submit_job.route('/submit_job/send', methods=['POST'])
@login_required
def send_job():
    try:
        job_to_submit = base64.b64decode(request.form["job_script"]).decode()
    except Exception as err:
        flash("Unable to read the job script due to: " + str(err), "error")
        return redirect("/my_files")

    required_parameters = ["cpus", "instance_type"]
    for param in required_parameters:
        if param not in request.form:
            flash("You must specify cpus and instance_type parameters", "error")
            return redirect("/my_files")

    cpus = request.form["cpus"]
    instance_type = request.form["instance_type"]
    if cpus is None:
        nodect = 1
    else:
        cpus_count_pattern = re.search(r'[.](\d+)', instance_type)
        if cpus_count_pattern:
            cpu_per_system = int(cpus_count_pattern.group(1)) * 2
        else:
            cpu_per_system = 2
        nodect = math.ceil(int(cpus) / cpu_per_system)

    for param in request.form:
        if param != "csrf_token":
            job_to_submit = job_to_submit.replace("%" + param + "%", request.form[param])

    payload = base64.b64encode(job_to_submit.encode()).decode()
    send_to_to_queue = post(config.Config.FLASK_ENDPOINT + "/api/scheduler/job",
                        headers={"X-SOCA-TOKEN": session["api_key"],
                                "X-SOCA-USER": session["user"]},
                        data={"payload": payload},
                        verify=False)
    if send_to_to_queue.status_code == 200:
        flash("Job submitted to the queue with ID: " + send_to_to_queue.json()["message"], "success")
    else:
        flash("Error during job submission: " + str(send_to_to_queue.json()["message"]), "error")

    return redirect("/my_jobs")