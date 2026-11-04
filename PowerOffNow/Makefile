TARGET = iphone:clang:latest:14.0
ARCHS = arm64 arm64e

INSTALL_TARGET_PROCESSES = PowerOffNow

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = PowerOffNow

PowerOffNow_FILES = AppDelegate.swift PowerOffViewController.swift DeviceController.m
PowerOffNow_FRAMEWORKS = UIKit
PowerOffNow_SWIFT_BRIDGING_HEADER = PowerOffNow-Bridging-Header.h
include $(THEOS_MAKE_PATH)/application.mk

$(APPLICATION_NAME)_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/aggregate.mk

before-package::
	@H="$(THEOS_STAGING_DIR)/Applications/PowerOffNow.app/PowerOffHelper"; \
	if [ -f "$$H" ]; then chmod +x "$$H"; echo "PowerOffHelper 已就位"; \
	else echo "警告：bundles 里没有 PowerOffHelper，检查是否先编译了 helper"; fi

after-package::
	@echo "Renaming .ipa to .tipa..."
	@cd ./packages && for f in *.ipa; do mv "$$f" "$${f%.ipa}.tipa"; done || echo "No .ipa file found."
