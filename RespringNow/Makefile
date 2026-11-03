TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = RespringNow

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = RespringNow

RespringNow_FILES = AppDelegate.swift RespringViewController.swift DeviceController.m
RespringNow_FRAMEWORKS = UIKit
RespringNow_SWIFT_BRIDGING_HEADER = RespringNow-Bridging-Header.h
include $(THEOS_MAKE_PATH)/application.mk

$(APPLICATION_NAME)_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/aggregate.mk

after-package::
	@echo "Renaming .ipa to .tipa..."
	@cd ./packages && for f in *.ipa; do mv "$$f" "$${f%.ipa}.tipa"; done || echo "No .ipa file found."
