ARCHS := arm64
PACKAGE_FORMAT := ipa
TARGET := iphone:clang:16.5:15.0

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = MultiWindow

MultiWindow_FILES = \
  AppDelegate.m \
  AppSceneViewController.m \
  DecoratedAppSceneView.m \
  DecoratedFloatingView.m \
  Hooks.m \
  LauncherViewController.m \
  MWLogViewerViewController.m \
  PiPManager.m \
  ResizeHandleView.m \
  SceneDelegate.m \
  ViewController.m \
  main.m
MultiWindow_FRAMEWORKS = UIKit
MultiWindow_PRIVATE_FRAMEWORKS = CoreServices FrontBoard RunningBoardServices
MultiWindow_CFLAGS = -fcommon -fobjc-arc -Iinclude -I. -Wno-error
# MultiWindow_LDFLAGS =
MultiWindow_CODESIGN_FLAGS = -Sentitlements.xml

include $(THEOS_MAKE_PATH)/application.mk
