TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = LockNow

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = LockNow

LockNow_FILES = AppDelegate.swift LockViewController.swift DeviceController.m
LockNow_FRAMEWORKS = UIKit
LockNow_SWIFT_BRIDGING_HEADER = LockNow-Bridging-Header.h
include $(THEOS_MAKE_PATH)/application.mk

$(APPLICATION_NAME)_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/aggregate.mk

after-package::
	@echo "Renaming .ipa to .tipa..."
	@cd ./packages && for f in *.ipa; do mv "$$f" "$${f%.ipa}.tipa"; done || echo "No .ipa file found."
