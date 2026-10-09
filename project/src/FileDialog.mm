#if defined(IPHONE) || defined(IPHONEOS) || defined(HX_IOS)

#import <UIKit/UIKit.h>

#include <ui/FileDialogEvent.h>

#include <system/CFFI.h>
#include <system/ValuePointer.h>
#include <hx/CFFIAPI.h>

#include <stdlib.h>
#include <string.h>
#include <string>
#include <vector>


using namespace lime;


static NSMutableArray* g_fileDialogObservers = nil;


@interface FileDialogObserver : NSObject <UIDocumentPickerDelegate>

@property (nonatomic) int handle;
@property (nonatomic) int eventType;
@property (nonatomic) BOOL multiple;
@property (nonatomic) BOOL saveMode;
@property (nonatomic, copy) NSString* savePath;

@end


@implementation FileDialogObserver


- (void)documentPicker:(UIDocumentPickerViewController*)controller
	didPickDocumentsAtURLs:(NSArray<NSURL*>*)urls
{
	[self handlePickedURLs:urls];
}


- (void)documentPicker:(UIDocumentPickerViewController*)controller
	didPickDocumentURLs:(NSArray<NSURL*>*)urls
{
	// Older iOS compatibility.
	[self handlePickedURLs:urls];
}


- (void)documentPickerWasCancelled:(UIDocumentPickerViewController*)controller
{
	int cancelType = self.saveMode ? FILE_SAVE_CANCELED : FILE_OPEN_CANCELED;
	[self dispatchEvent:cancelType file:""];
	[self removeFromGlobals];
}


- (void)handlePickedURLs:(NSArray<NSURL*>*)urls
{
	if (urls == nil || urls.count == 0)
	{
		int cancelType = self.saveMode ? FILE_SAVE_CANCELED : FILE_OPEN_CANCELED;
		[self dispatchEvent:cancelType file:""];
		[self removeFromGlobals];
		return;
	}

	if (self.saveMode)
	{
		NSURL* destination = urls.firstObject;

		if (destination == nil)
		{
			[self dispatchEvent:FILE_SAVE_ERROR file:""];
			[self removeFromGlobals];
			return;
		}

		if (![destination startAccessingSecurityScopedResource])
		{
			[self dispatchEvent:FILE_SAVE_ERROR file:""];
			[self removeFromGlobals];
			return;
		}

		NSError* error = nil;
		NSFileManager* fm = [NSFileManager defaultManager];

		if ([fm fileExistsAtPath:destination.path])
		{
			[fm removeItemAtURL:destination error:&error];
			error = nil;
		}

		NSURL* source = [NSURL fileURLWithPath:self.savePath];
		BOOL ok = [fm copyItemAtURL:source toURL:destination error:&error];

		[destination stopAccessingSecurityScopedResource];

		if (ok)
		{
			[self dispatchEvent:FILE_SAVE_SUCCESS file:destination.path.UTF8String];
		}
		else
		{
			[self dispatchEvent:FILE_SAVE_ERROR file:""];
		}

		[self removeFromGlobals];
		return;
	}

	if (self.multiple)
	{
		NSMutableString* joined = [NSMutableString string];
		BOOL first = YES;

		for (NSURL* url in urls)
		{
			NSString* tempPath = [self copyURLToTemp:url fallbackName:nil];

			if (tempPath == nil)
			{
				continue;
			}

			if (!first)
			{
				[joined appendString:@"\n"];
			}

			[joined appendString:tempPath];
			first = NO;
		}

		if (first)
		{
			[self dispatchEvent:FILE_OPEN_ERROR file:""];
		}
		else
		{
			[self dispatchEvent:self.eventType file:joined.UTF8String];
		}

	}
	else
	{
		NSURL* url = urls.firstObject;
		NSString* tempPath = [self copyURLToTemp:url fallbackName:nil];

		if (tempPath == nil)
		{
			[self dispatchEvent:FILE_OPEN_ERROR file:""];
		}
		else
		{
			[self dispatchEvent:self.eventType file:tempPath.UTF8String];
		}

	}

	[self removeFromGlobals];
}


- (NSString*)copyURLToTemp:(NSURL*)url fallbackName:(NSString*)fallbackName
{
	if (url == nil)
	{
		return nil;
	}

	if (![url startAccessingSecurityScopedResource])
	{
		return nil;
	}

	NSString* name = url.lastPathComponent;

	if (name == nil || name.length == 0)
	{
		name = fallbackName != nil ? fallbackName : [[NSUUID UUID] UUIDString];
	}

	// Remove SAF colon-separated junk if present.
	if ([name rangeOfString:@":"].location != NSNotFound)
	{
		NSArray* parts = [name componentsSeparatedByString:@":"];

		if (parts != nil && parts.count > 1)
		{
			name = parts.lastObject;
		}
	}

	NSString* tmpDir = NSTemporaryDirectory();
	NSString* destPath = [tmpDir stringByAppendingPathComponent:name];
	NSURL* destURL = [NSURL fileURLWithPath:destPath];

	NSFileManager* fm = [NSFileManager defaultManager];
	NSError* error = nil;

	int counter = 1;

	while ([fm fileExistsAtPath:destPath])
	{
		NSString* base = name.pathExtension.length > 0 ? name.stringByDeletingPathExtension : name;
		NSString* ext = name.pathExtension;

		NSString* newName = ext.length > 0
			? [NSString stringWithFormat:@"%@_%d.%@", base, counter, ext]
			: [NSString stringWithFormat:@"%@_%d", base, counter];

		destPath = [tmpDir stringByAppendingPathComponent:newName];
		destURL = [NSURL fileURLWithPath:destPath];
		counter++;
	}

	if ([fm fileExistsAtPath:destPath])
	{
		[fm removeItemAtURL:destURL error:nil];
	}

	BOOL ok = [fm copyItemAtURL:url toURL:destURL error:&error];

	[url stopAccessingSecurityScopedResource];

	return ok ? destPath : nil;
}


- (void)dispatchEvent:(int)type file:(const char*)file
{
	FileDialogEvent event;
	event.id = self.handle;
	event.type = (FileDialogEventType)type;

	char* copy = strdup(file != nullptr ? file : "");
	event.file = (vbyte*)copy;

	FileDialogEvent::Dispatch(&event);

	free(copy);
	event.file = nullptr;
}


- (void)removeFromGlobals
{
	if (g_fileDialogObservers != nil)
	{
		[g_fileDialogObservers removeObject:self];
	}
}


@end


static FileDialogObserver* findObserver(int handle)
{
	if (g_fileDialogObservers == nil)
	{
		return nil;
	}

	for (FileDialogObserver* observer in g_fileDialogObservers)
	{
		if (observer.handle == handle)
		{
			return observer;
		}
	}

	return nil;
}


static FileDialogObserver* createObserver(int handle)
{
	if (g_fileDialogObservers == nil)
	{
		g_fileDialogObservers = [[NSMutableArray alloc] init];
	}

	FileDialogObserver* observer = [[FileDialogObserver alloc] init];
	observer.handle = handle;

	[g_fileDialogObservers addObject:observer];

	return observer;
}


static UIViewController* topViewController(void)
{
	UIWindow* window = nil;

	if (@available(iOS 13.0, *))
	{
		for (UIScene* scene in UIApplication.sharedApplication.connectedScenes)
		{
			if (scene.activationState != UISceneActivationStateForegroundActive)
			{
				continue;
			}

			if (![scene isKindOfClass:[UIWindowScene class]])
			{
				continue;
			}

			UIWindowScene* windowScene = (UIWindowScene*)scene;

			for (UIWindow* w in windowScene.windows)
			{
				if (w.isKeyWindow)
				{
					window = w;
					break;
				}
			}

			if (window != nil)
			{
				break;
			}
		}
	}

	if (window == nil)
	{
		window = UIApplication.sharedApplication.keyWindow;
	}

	UIViewController* controller = window.rootViewController;

	while (controller.presentedViewController != nil)
	{
		controller = controller.presentedViewController;
	}

	return controller;
}


static void presentFileDialog(
	int handle,
	BOOL openMode,
	BOOL multiple,
	BOOL saveMode,
	NSString* savePath,
	int eventType
)
{
	@autoreleasepool
	{
		FileDialogObserver* observer = createObserver(handle);
		observer.eventType = eventType;
		observer.multiple = multiple;
		observer.saveMode = saveMode;
		observer.savePath = savePath;

		UIDocumentPickerViewController* picker = nil;

		if (saveMode)
		{
			NSURL* url = [NSURL fileURLWithPath:savePath];
			picker = [[UIDocumentPickerViewController alloc] initWithForExportingURLs:@[url] asCopy:YES];
		}
		else
		{
			NSArray<NSString*>* documentTypes = multiple
				? @[@"public.item", @"public.folder"]
				: @[@"public.item"];

			picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:documentTypes
																				inMode:UIDocumentPickerModeOpen];

			if (@available(iOS 11.0, *))
			{
				picker.allowsMultipleSelection = multiple;
			}
		}

		picker.delegate = observer;

		UIViewController* vc = topViewController();

		if (vc != nil)
		{
			[vc presentViewController:picker animated:YES completion:nil];
		}
		else
		{
			int errorType = saveMode ? FILE_SAVE_ERROR : FILE_OPEN_ERROR;
			observer.eventType = errorType;
			[observer dispatchEvent:errorType file:""];
			[observer removeFromGlobals];
		}
	}
}


extern "C" {


	value lime_file_dialog_create_ios()
	{
		static int nextHandle = 1;
		return alloc_int(nextHandle++);
	}


	value lime_file_dialog_open_ios(value inHandle)
	{
		int handle = val_int(inHandle);
		presentFileDialog(handle, YES, NO, NO, nil, FILE_OPEN_SUCCESS);
		return val_null;
	}


	value lime_file_dialog_browse_select_ios(value inHandle)
	{
		int handle = val_int(inHandle);
		presentFileDialog(handle, YES, NO, NO, nil, FILE_BROWSE_SELECT);
		return val_null;
	}


	value lime_file_dialog_browse_select_multiple_ios(value inHandle)
	{
		int handle = val_int(inHandle);
		presentFileDialog(handle, YES, YES, NO, nil, FILE_BROWSE_SELECT_MULTIPLE);
		return val_null;
	}


	value lime_file_dialog_save_ios(value inHandle, value inPath)
	{
		int handle = val_int(inHandle);
		const char* path = val_string(inPath);

		if (path == nullptr)
		{
			return val_null;
		}

		presentFileDialog(handle, NO, NO, YES, [NSString stringWithUTF8String:path], FILE_SAVE_SUCCESS);
		return val_null;
	}


	value lime_file_dialog_browse_save_ios(value inHandle, value inPath)
	{
		int handle = val_int(inHandle);
		const char* path = val_string(inPath);

		if (path == nullptr)
		{
			return val_null;
		}

		presentFileDialog(handle, NO, NO, YES, [NSString stringWithUTF8String:path], FILE_SAVE_SUCCESS);
		return val_null;
	}


	value lime_file_dialog_manager_register_ios(value inCallback, value inEventObject)
	{
		if (FileDialogEvent::callback != nullptr)
		{
			delete FileDialogEvent::callback;
		}

		if (FileDialogEvent::eventObject != nullptr)
		{
			delete FileDialogEvent::eventObject;
		}

		FileDialogEvent::callback = new ValuePointer(inCallback);
		FileDialogEvent::eventObject = new ValuePointer(inEventObject);

		return val_null;
	}


}

DEFINE_PRIM(lime_file_dialog_create_ios, 0);
DEFINE_PRIM(lime_file_dialog_open_ios, 1);
DEFINE_PRIM(lime_file_dialog_browse_select_ios, 1);
DEFINE_PRIM(lime_file_dialog_browse_select_multiple_ios, 1);
DEFINE_PRIM(lime_file_dialog_save_ios, 2);
DEFINE_PRIM(lime_file_dialog_browse_save_ios, 2);
DEFINE_PRIM(lime_file_dialog_manager_register_ios, 2);
#endif