import io
import os
from urllib.parse import urlparse

import environ

# Import the original settings from each template
from .basesettings import *

env = environ.Env()
environ.Env.read_env("/appvar/.env")

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

# Define static storage via django-storages[google]
GS_BUCKET_NAME = env("WAG_BUCKET_NAME")
STATICFILES_DIRS = []
DEFAULT_FILE_STORAGE = "storages.backends.gcloud.GoogleCloudStorage"
STATICFILES_STORAGE = "storages.backends.gcloud.GoogleCloudStorage"
GS_DEFAULT_ACL = "publicRead"