
export ARCHS = armv7 arm64

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = KeyLogin
KeyLogin_FILES = Tweak.xm
KeyLogin_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
