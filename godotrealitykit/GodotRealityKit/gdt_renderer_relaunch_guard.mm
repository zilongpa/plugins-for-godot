//===----------------------------------------------------------------------===//
// Copyright © 2026 Apple Inc.
//
// Licensed under the MIT license (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// LICENSE
//
//===----------------------------------------------------------------------===//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

static NSString *const kGDRKRendererRelaunchDetectedNotification = @"GDRKRendererRelaunchDetected";

namespace {

void swizzle_boot_logo_as_relaunch(Class cls, SEL selector) {
	Method method = class_getInstanceMethod(cls, selector);
	if (!method) {
		NSLog(@"GodotRealityKit: cannot install relaunch guard, missing -[%@ %@]",
				NSStringFromClass(cls), NSStringFromSelector(selector));
		return;
	}

	IMP guarded_imp = imp_implementationWithBlock(^(id self, BOOL p_show_boot_logo) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[[NSNotificationCenter defaultCenter]
					postNotificationName:kGDRKRendererRelaunchDetectedNotification
								  object:nil];
		});
	});
	method_setImplementation(method, guarded_imp);
}

void swizzle_one_shot_void(Class cls, SEL selector, dispatch_once_t *guard) {
	Method method = class_getInstanceMethod(cls, selector);
	if (!method) {
		NSLog(@"GodotRealityKit: cannot install relaunch guard, missing -[%@ %@]",
				NSStringFromClass(cls), NSStringFromSelector(selector));
		return;
	}

	__block IMP original_imp = method_getImplementation(method);
	IMP guarded_imp = imp_implementationWithBlock(^(id self) {
		dispatch_once(guard, ^{
			((void (*)(id, SEL))original_imp)(self, selector);
		});
	});
	method_setImplementation(method, guarded_imp);
}

} // namespace

namespace gdrk {

void install_renderer_relaunch_guard() {
	static dispatch_once_t install_once;
	dispatch_once(&install_once, ^{
		Class renderer_cls = NSClassFromString(@"GDTRenderer");
		if (!renderer_cls) {
			return;
		}

		swizzle_boot_logo_as_relaunch(renderer_cls, @selector(setUpProjectDataShowingBootLogo:));

		static dispatch_once_t start_guard;
		swizzle_one_shot_void(renderer_cls, @selector(startMain), &start_guard);
	});
}

} // namespace gdrk
