
import os
from django.core.management import execute_from_command_line
import urllib.parse
import environ
from .wsgi import application


os.environ.setdefault("DJANGO_SETTINGS_MODULE", "test1.settings.dev")

def app(requestEnviron, start_response):

    if requestEnviron['PATH_INFO'] == "/util-manage":

        env = environ.Env()
        environ.Env.read_env("/appvar/.env")

        if env("ENABLE_MANAGE_ENDPOINT", default='0') != "1" :
            return application(requestEnviron,start_response)

        query=requestEnviron['QUERY_STRING'].split("&")

        args={}
        for q in query:
            parts=q.split("=",2)
            args[parts[0]]=urllib.parse.unquote_plus(parts[1])

        key=env("MANAGE_SECRET_KEY", default='')

        

        if (not key) or ("key" not in args) or (key != args["key"]) :

            status = "401 Unauthorized"
            data = b'"invalid key"'

        else:

            if "args" in args:
                exeArgs=args["args"].split(",")
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
        

    
    