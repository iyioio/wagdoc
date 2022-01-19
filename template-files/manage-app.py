
import os
from django.core.management import execute_from_command_line
import urllib.parse
import environ
import json
from .wsgi import application


os.environ.setdefault("DJANGO_SETTINGS_MODULE", "[[APP_NAME]].settings")

def app(requestEnviron, start_response):

    if requestEnviron['PATH_INFO'] == "/util-manage":

        env = environ.Env()
        environ.Env.read_env("/appvar/.env")

        if env("ENABLE_MANAGE_ENDPOINT", default='0') != "1" :
            return application(requestEnviron,start_response)

        try:
            request_body_size = int(requestEnviron.get('CONTENT_LENGTH', 0))
        except (ValueError):
            request_body_size = 0

        request_body = requestEnviron['wsgi.input'].read(request_body_size).decode("utf-8")
        request = json.loads(request_body)

        key=env("MANAGE_SECRET_KEY", default='')
        

        if (not key) or ("key" not in request) or (key != request["key"]) :

            status = "401 Unauthorized"
            data = b'"invalid key"'

        else:

            if "args" in request:
                exeArgs=request["args"]
                exeArgs.insert(0,"manage.py")
                execute_from_command_line(exeArgs)
                status = "200 OK"
                data = b'"success"'
            else:
                status = "400 Bad Request"
                data = b'"args param required"'

        start_response(status, [
            ("Content-Type", "application/json"),
            ("Content-Length", str(len(data)))
        ])
        return iter([data])


    return application(requestEnviron,start_response)
    