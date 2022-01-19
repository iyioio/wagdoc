from wagtail.api.v2.views import PagesAPIViewSet
from wagtail.api.v2.router import WagtailAPIRouter
from wagtail.images.api.v2.views import ImagesAPIViewSet
from wagtail.documents.api.v2.views import DocumentsAPIViewSet

from rest_framework.renderers import JSONRenderer

# Create the router. "wagtailapi" is the URL namespace
api_router = WagtailAPIRouter('wagtailapi')

# The custom JsonXX classes below override renderer_classes so that JSON is returned for all 
# requesting clients including web browsers

class JsonPagesAPIViewSet(PagesAPIViewSet):
    renderer_classes = [JSONRenderer]

class JsonImagesAPIViewSet(ImagesAPIViewSet):
    renderer_classes = [JSONRenderer]

class JsonDocumentsAPIViewSet(DocumentsAPIViewSet):
    renderer_classes = [JSONRenderer]


api_router.register_endpoint('pages', JsonPagesAPIViewSet)
api_router.register_endpoint('images', JsonImagesAPIViewSet)
api_router.register_endpoint('documents', JsonDocumentsAPIViewSet)