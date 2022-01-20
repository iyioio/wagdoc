import io
import os
from urllib.parse import urlparse

import environ

# Import the original settings from each template
from .settings_base import *

try:
    from .settings_local import *
except ImportError:
    pass

env = environ.Env()

if env('WAG_USE_CONFIG', default='0') == "1" :

    environ.Env.read_env("/appvar/.env")

    appName=env('WAG_APP_NAME')

    SECRET_KEY = env("SECRET_KEY")

    DATABASES = {
        'default': {
            'ENGINE': env('WAG_ENGINE'),
            'NAME': env('WAG_NAME'),
            'USER': env('WAG_USER'),
            'PASSWORD': env('WAG_PASSWORD'),
            'HOST': env('WAG_HOST'),
            'PORT': env('WAG_PORT'),
        }
    }

    ALLOWED_HOSTS = ["*"]

    DEBUG = env("WAG_DEBUG", default=False) == '1'

    if appName not in INSTALLED_APPS:
        INSTALLED_APPS += [appName] # for custom data migration

    if 'wagtail.api.v2' not in INSTALLED_APPS:
        INSTALLED_APPS += ['wagtail.api.v2']

    # Define static storage via django-storages[google]
    GS_BUCKET_NAME = env("WAG_BUCKET_NAME")
    STATICFILES_DIRS = []
    DEFAULT_FILE_STORAGE = "storages.backends.gcloud.GoogleCloudStorage"
    STATICFILES_STORAGE = "storages.backends.gcloud.GoogleCloudStorage"
    GS_DEFAULT_ACL = "publicRead"

else:
    ## The settings below should only be used for development
    SECRET_KEY = '__NOT_A_SECRET__'
    DEBUG = True
    