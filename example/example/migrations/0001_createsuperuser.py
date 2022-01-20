import os

from django.contrib.auth.models import User
from django.db import migrations
from django.utils import timezone


def createsuperuser(apps, schema_editor):
    admin_password = os.environ["WAG_ADMIN_PASSWORD"] 
    User.objects.create_superuser("admin", password=admin_password, last_login=timezone.now())


class Migration(migrations.Migration):

    initial = True

    dependencies = [
    ]

    operations = [
        migrations.RunPython(createsuperuser)
    ]