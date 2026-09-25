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

void notify_renderer_relaunch() {
	dispatch_async(dispatch_get_main_queue(), ^{
		[[NSNotificationCenter defaultCenter]
			postNotificationName:kGDRKRendererRelaunchDetectedNotification object:nil];
	});
}

void swizzle_project_data_as_relaunch(Class cls) {
	SEL selector = @selector(setUpProjectDataShowingBootLogo:);
	Method method = class_getInstanceMethod(cls, selector);
	if (method) {
		IMP guarded_imp = imp_implementationWithBlock(^(id self, BOOL p_show_boot_logo) {
			notify_renderer_relaunch();
		});
		method_setImplementation(method, guarded_imp);
		return;
	}

	selector = @selector(setUpProjectData);
	method = class_getInstanceMethod(cls, selector);
	if (method) {
		IMP guarded_imp = imp_implementationWithBlock(^(id self) {
			notify_renderer_relaunch();
		});
		method_setImplementation(method, guarded_imp);
		return;
	}
	NSLog(@"GodotRealityKit: cannot install relaunch guard; no project-data setup method on %@",
			NSStringFromClass(cls));
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

		swizzle_project_data_as_relaunch(renderer_cls);

		static dispatch_once_t start_guard;
		swizzle_one_shot_void(renderer_cls, @selector(startMain), &start_guard);
	});
}

} // namespace gdrk
