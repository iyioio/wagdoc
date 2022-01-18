import os
# Import the original settings from each template
from .basesettings import *

DATABASES = {
    'default': {
        'ENGINE': '[[ENGINE]]',
        'NAME': '[[NAME]]',
        'USER': '[[USER]]',
        'PASSWORD': os.environ.get('[[PASSWORD_VAR]]'),
        'HOST': '[[HOST]]',
        'PORT': '[[PORT]]',
    }
}

# Define static storage via django-storages[google]
GS_BUCKET_NAME = os.environ.get("GS_BUCKET_NAME")
STATICFILES_DIRS = []
DEFAULT_FILE_STORAGE = "storages.backends.gcloud.GoogleCloudStorage"
STATICFILES_STORAGE = "storages.backends.gcloud.GoogleCloudStorage"
GS_DEFAULT_ACL = "publicRead"