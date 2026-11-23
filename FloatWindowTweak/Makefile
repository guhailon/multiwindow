ARCHS = arm64 arm64e
TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = MWFloat

MWFloat_FILES = Tweak.x MWFloatGrabber.m MWBackgrounderManager.m MWSceneHelper.m MWPassthroughWindow.m MWWindowView.m MWThemeManager.m
MWFloat_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-arc-performSelector-leaks
MWFloat_FRAMEWORKS = UIKit CoreGraphics QuartzCore

include $(THEOS_MAKE_PATH)/tweak.mk
