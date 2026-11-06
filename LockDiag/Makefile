TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = LockDiag

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = LockDiag

# 纯 Objective-C：不使用 Swift、不使用 bridging header，排除整条 Swift 运行时链路
LockDiag_FILES = main.m AppDelegate.m DiagViewController.m
LockDiag_FRAMEWORKS = UIKit
include $(THEOS_MAKE_PATH)/application.mk

$(APPLICATION_NAME)_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/aggregate.mk

after-package::
	@echo "Renaming .ipa to .tipa..."
	@cd ./packages && for f in *.ipa; do mv "$$f" "$${f%.ipa}.tipa"; done || echo "No .ipa file found."
