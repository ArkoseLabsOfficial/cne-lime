package lime.ui;

import haxe.io.Bytes;
import haxe.io.Path;
import haxe.ds.Map;
import lime._internal.backend.native.NativeCFFI;
import lime.app.Event;
import lime.graphics.Image;
import lime.system.CFFI;
import lime.system.System;
import lime.system.ThreadPool;
import lime.utils.ArrayBuffer;
import lime.utils.Resource;

#if android
import lime.system.JNI;
#end

#if hl
import hl.Bytes as HLBytes;
import hl.NativeArray;
#end

#if sys
import sys.io.File;
#end

#if (js && html5)
import js.html.Blob;
#end

/**
	Simple file dialog used for asking user where to save a file, or select files to open.

	This class supports both:

	- The new SDL3 static API:
		- `FileDialog.openFile()`
		- `FileDialog.openDirectory()`
		- `FileDialog.saveFile()`

	- The old SDL2 instance API:
		- `new FileDialog()`
		- `browse()`
		- `open()`
		- `save()`
**/
#if !lime_debug
@:fileXml('tags="haxe,release"')
@:noDebug
#end
@:access(lime._internal.backend.native.NativeCFFI)
@:access(lime.graphics.Image)
@:access(lime.ui.Window)
class FileDialog #if android implements JNISafety #end
{
	/* ------------------------------------------------------------------------
		Legacy SDL2 instance events
	------------------------------------------------------------------------ */

	public var onCancel = new Event<Void->Void>();
	public var onOpen = new Event<Resource->Void>();
	public var onSave = new Event<String->Void>();
	public var onSelect = new Event<String->Void>();
	public var onSelectMultiple = new Event<Array<String>->Void>();

	#if android
	private static final OPEN_REQUEST_CODE:Int = JNI.createStaticField('org/haxe/lime/FileDialog', 'OPEN_REQUEST_CODE', 'I').get();
	private static final OPEN_MULTIPLE_REQUEST_CODE:Int = JNI.createStaticField('org/haxe/lime/FileDialog', 'OPEN_MULTIPLE_REQUEST_CODE', 'I').get();
	private static final SAVE_REQUEST_CODE:Int = JNI.createStaticField('org/haxe/lime/FileDialog', 'SAVE_REQUEST_CODE', 'I').get();
	private static final DOCUMENT_TREE_REQUEST_CODE:Int = JNI.createStaticField('org/haxe/lime/FileDialog', 'DOCUMENT_TREE_REQUEST_CODE', 'I').get();
	private static final RESULT_OK:Int = -1;

	private var JNI_FILE_DIALOG:Dynamic = null;
	private var IS_SELECT:Bool = false;
	#elseif ios
	private static var registeredEvents:Bool = false;
	private static var eventHandler:FileDialogEventHanlder;
	private static var fileDialogInstances:Map<Int, FileDialog> = new Map<Int, FileDialog>();

	private var native_id:Int = -1;
	public var isBrowseSave:Bool = false;
	#end

	public function new()
	{
		#if android
		JNI_FILE_DIALOG = JNI.createStaticMethod('org/haxe/lime/FileDialog', 'createInstance', '(Lorg/haxe/lime/HaxeObject;)Lorg/haxe/lime/FileDialog;')(this);
		#elseif ios
		if (!registeredEvents)
		{
			eventHandler = new FileDialogEventHanlder();
			registeredEvents = true;
		}

		native_id = NativeCFFI.lime_file_dialog_create_ios();
		fileDialogInstances.set(native_id, this);
		#end
	}

	/* ------------------------------------------------------------------------
		New SDL3 static API
	------------------------------------------------------------------------ */

	/**
		Opens a directory selection dialog.

		On desktop this uses SDL3's native file dialog.
		On mobile this is bridged to the legacy SDL2 mobile implementation.
	**/
	public static function openDirectory(window:Window = null, title:String = null, callback:Array<String>->Void = null,
			defaultPath:String = null, allowMultiple:Bool = false):Void
	{
		#if (desktop && lime_cffi && !macro)
		var handle:Int = window != null ? window.__backend.handle : 0;

		if (defaultPath == null)
		{
			defaultPath = Sys.getCwd();
		}

		#if hl
		var dialogCallback = function(list:hl.NativeArray<hl.Bytes>):Void
		{
			if (callback != null)
			{
				var paths:Array<String> = [];

				if (list != null)
				{
					for (i in 0...list.length)
					{
						paths.push(CFFI.stringValue(list[i]));
					}
				}

				callback(paths);
			}
		};
		#else
		var dialogCallback = function(list:Array<String>):Void
		{
			if (callback != null)
			{
				callback(list != null ? list : []);
			}
		};
		#end

		NativeCFFI.lime_file_dialog_open_directory(handle, title, dialogCallback, defaultPath, allowMultiple);
		#elseif (android || ios)
		__mobileOpenDirectory(title, callback, defaultPath, allowMultiple);
		#else
		if (callback != null) callback([]);
		#end
	}

	/**
		Opens a file selection dialog.

		On desktop this uses SDL3's native file dialog.
		On mobile this is bridged to the legacy SDL2 mobile implementation.
	**/
	public static function openFile(window:Window = null, title:String = null,
			callback:Array<String>->FileDialogFilter->Void = null, filters:Array<FileDialogFilter> = null,
			defaultPath:String = null, allowMultiple:Bool = false):Void
	{
		#if (desktop && lime_cffi && !macro)
		var handle:Int = window != null ? window.__backend.handle : 0;

		if (defaultPath == null)
		{
			defaultPath = Sys.getCwd();
		}

		var count:Int = filters != null ? filters.length : 0;

		#if hl
		var names = new hl.NativeArray<String>(count);
		var patterns = new hl.NativeArray<String>(count);

		for (i in 0...count)
		{
			names[i] = filters[i].name;
			patterns[i] = filters[i].pattern;
		}

		var dialogCallback = function(list:hl.NativeArray<hl.Bytes>, filterIndex:Int):Void
		{
			if (callback != null)
			{
				var files:Array<String> = [];

				if (list != null)
				{
					for (i in 0...list.length)
					{
						files.push(CFFI.stringValue(list[i]));
					}
				}

				var filter:FileDialogFilter = null;

				if (filters != null && filterIndex >= 0 && filterIndex < filters.length)
				{
					filter = filters[filterIndex];
				}

				callback(files, filter);
			}
		};
		#else
		var names:Array<String> = filters != null ? filters.map(f -> f.name) : [];
		var patterns:Array<String> = filters != null ? filters.map(f -> f.pattern) : [];

		var dialogCallback = function(filelist:Array<String>, filterIndex:Int):Void
		{
			if (callback != null)
			{
				var files:Array<String> = filelist != null ? filelist : [];

				var filter:FileDialogFilter = null;

				if (filters != null && filterIndex >= 0 && filterIndex < filters.length)
				{
					filter = filters[filterIndex];
				}

				callback(files, filter);
			}
		};
		#end

		NativeCFFI.lime_file_dialog_open_file(handle, title, dialogCallback, names, patterns, count, defaultPath, allowMultiple);
		#elseif (android || ios)
		__mobileOpenFile(title, callback, filters, defaultPath, allowMultiple);
		#else
		if (callback != null) callback([], null);
		#end
	}

	/**
		Opens a save file dialog.

		On desktop this uses SDL3's native file dialog.
		On mobile this is bridged to the legacy SDL2 mobile implementation.

		Note:
		On Android, the returned string may be a best-effort filesystem path or a content-style path
		depending on the platform implementation. For maximum compatibility with old SDL2 mobile code,
		prefer the legacy `save(data)` API on Android when you already have the bytes to write.
	**/
	public static function saveFile(window:Window = null, title:String = null,
			callback:String->FileDialogFilter->Void = null, filters:Array<FileDialogFilter> = null,
			defaultPath:String = null):Void
	{
		#if (desktop && lime_cffi && !macro)
		var handle:Int = window != null ? window.__backend.handle : 0;

		if (defaultPath == null)
		{
			defaultPath = Sys.getCwd();
		}

		var count:Int = filters != null ? filters.length : 0;

		#if hl
		var names = new hl.NativeArray<String>(count);
		var patterns = new hl.NativeArray<String>(count);

		for (i in 0...count)
		{
			names[i] = filters[i].name;
			patterns[i] = filters[i].pattern;
		}

		var dialogCallback = function(filename:hl.Bytes, filterIndex:Int):Void
		{
			if (callback != null)
			{
				var path:String = filename != null ? CFFI.stringValue(filename) : null;

				var filter:FileDialogFilter = null;

				if (filters != null && filterIndex >= 0 && filterIndex < filters.length)
				{
					filter = filters[filterIndex];
				}

				callback(__applySaveFilterExtension(path, filter), filter);
			}
		};
		#else
		var names:Array<String> = filters != null ? filters.map(f -> f.name) : [];
		var patterns:Array<String> = filters != null ? filters.map(f -> f.pattern) : [];

		var dialogCallback = function(filename:String, filterIndex:Int):Void
		{
			if (callback != null)
			{
				var filter:FileDialogFilter = null;

				if (filters != null && filterIndex >= 0 && filterIndex < filters.length)
				{
					filter = filters[filterIndex];
				}

				callback(__applySaveFilterExtension(filename, filter), filter);
			}
		};
		#end

		NativeCFFI.lime_file_dialog_save_file(handle, title, dialogCallback, names, patterns, count, defaultPath);
		#elseif (android || ios)
		__mobileSaveFile(title, callback, filters, defaultPath);
		#else
		if (callback != null) callback(null, null);
		#end
	}

	/* ------------------------------------------------------------------------
		Legacy SDL2 instance API
	------------------------------------------------------------------------ */

	public function browse(type:FileDialogType = null, filter:String = null, defaultPath:String = null, title:String = null):Bool
	{
		if (type == null) type = FileDialogType.OPEN;

		#if desktop
		switch (type)
		{
			case OPEN:
				FileDialog.openFile(null, title, function(paths, _)
				{
					if (paths != null && paths.length > 0)
					{
						onSelect.dispatch(paths[0]);
					}
					else
					{
						onCancel.dispatch();
					}
				},
				__filterFromString(filter), defaultPath, false);

				return true;

			case OPEN_MULTIPLE:
				FileDialog.openFile(null, title, function(paths, _)
				{
					if (paths != null && paths.length > 0)
					{
						onSelectMultiple.dispatch(paths);
					}
					else
					{
						onCancel.dispatch();
					}
				},
				__filterFromString(filter), defaultPath, true);

				return true;

			case OPEN_DIRECTORY:
				FileDialog.openDirectory(null, title, function(paths)
				{
					if (paths != null && paths.length > 0)
					{
						onSelect.dispatch(paths[0]);
					}
					else
					{
						onCancel.dispatch();
					}
				},
				defaultPath, false);

				return true;

			case SAVE:
				FileDialog.saveFile(null, title, function(path, _)
				{
					if (path != null)
					{
						onSelect.dispatch(path);
					}
					else
					{
						onCancel.dispatch();
					}
				},
				__filterFromString(filter), defaultPath);

				return true;
		}

		onCancel.dispatch();
		return false;

		#elseif android
		IS_SELECT = true;

		switch (type)
		{
			case OPEN:
				filter = StringTools.replace(filter, " ", "");
				JNI.callMember(JNI.createMemberMethod('org/haxe/lime/FileDialog', 'open',
					'(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V'),
					JNI_FILE_DIALOG, [filter, defaultPath, title]);
				return true;

			case OPEN_MULTIPLE:
				filter = StringTools.replace(filter, " ", "");
				JNI.callMember(JNI.createMemberMethod('org/haxe/lime/FileDialog', 'openMultiple',
					'(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V'),
					JNI_FILE_DIALOG, [filter, defaultPath, title]);
				return true;

			case OPEN_DIRECTORY:
				JNI.callMember(JNI.createMemberMethod('org/haxe/lime/FileDialog', 'openDocumentTree',
					'(Ljava/lang/String;)V'),
					JNI_FILE_DIALOG, [defaultPath]);
				return true;

			case SAVE:
				filter = StringTools.replace(filter, " ", "");
				JNI.callMember(JNI.createMemberMethod('org/haxe/lime/FileDialog', 'savePath',
					'(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V'),
					JNI_FILE_DIALOG, [filter, defaultPath, title]);
				return true;
		}

		onCancel.dispatch();
		return false;

		#elseif ios
		switch (type)
		{
			case OPEN:
				NativeCFFI.lime_file_dialog_browse_select_ios(native_id);
				return true;

			case OPEN_MULTIPLE:
				NativeCFFI.lime_file_dialog_browse_select_multiple_ios(native_id);
				return true;

			case SAVE:
				isBrowseSave = true;

				var titleStr = defaultPath != null ? Path.withoutDirectory(defaultPath) : (title != null ? title : "untitled");
				var tempPath = System.documentsDirectory + "/" + titleStr;

				sys.io.File.saveContent(tempPath, "");

				NativeCFFI.lime_file_dialog_browse_save_ios(native_id, tempPath);
				return true;

			default:
				onCancel.dispatch();
				return false;
		}
		#else
		onCancel.dispatch();
		return false;
		#end
	}

	public function open(filter:String = null, defaultPath:String = null, title:String = null):Bool
	{
		#if desktop
		FileDialog.openFile(null, title, function(paths, _)
		{
			if (paths != null && paths.length > 0)
			{
				try
				{
					var data = File.getBytes(paths[0]);
					onOpen.dispatch(data);
					return;
				}
				catch (e:Dynamic) {}
			}

			onCancel.dispatch();
		},
		__filterFromString(filter), defaultPath, false);

		return true;

		#elseif android
		IS_SELECT = false;
		filter = StringTools.replace(filter, " ", "");
		JNI.callMember(JNI.createMemberMethod('org/haxe/lime/FileDialog', 'open',
			'(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)V'),
			JNI_FILE_DIALOG, [filter, defaultPath, title]);
		return true;

		#elseif ios
		NativeCFFI.lime_file_dialog_open_ios(native_id);
		return true;

		#else
		onCancel.dispatch();
		return false;
		#end
	}

	public function save(data:Resource, filter:String = null, defaultPath:String = null, title:String = null,
			type:String = "application/octet-stream"):Bool
	{
		#if !android
		if (data == null)
		{
			onCancel.dispatch();
			return false;
		}
		#end

		#if desktop
		FileDialog.saveFile(null, title, function(path, _)
		{
			if (path != null)
			{
				try
				{
					File.saveBytes(path, data);
					onSave.dispatch(path);
					return;
				}
				catch (e:Dynamic) {}
			}

			onCancel.dispatch();
		},
		__filterFromString(filter), defaultPath);

		return true;

		#elseif (js && html5)
		var defaultExtension = "";

		if (Image.__isPNG(data))
		{
			type = "image/png";
			defaultExtension = ".png";
		}
		else if (Image.__isJPG(data))
		{
			type = "image/jpeg";
			defaultExtension = ".jpg";
		}
		else if (Image.__isGIF(data))
		{
			type = "image/gif";
			defaultExtension = ".gif";
		}
		else if (Image.__isWebP(data))
		{
			type = "image/webp";
			defaultExtension = ".webp";
		}

		var path = defaultPath != null ? Path.withoutDirectory(defaultPath) : "download" + defaultExtension;
		var buffer = (data : Bytes).getData();
		buffer = buffer.slice(0, (data : Bytes).length);

		#if commonjs
		untyped #if haxe4 js.Syntax.code #else __js__ #end ("require ('file-saver')")(new Blob([buffer], {type: type}), path, true);
		#else
		untyped window.saveAs(new Blob([buffer], {type: type}), path, true);
		#end

		onSave.dispatch(path);
		return true;

		#elseif android
		if (Image.__isPNG(data))
		{
			type = "image/png";
		}
		else if (Image.__isJPG(data))
		{
			type = "image/jpeg";
		}
		else if (Image.__isGIF(data))
		{
			type = "image/gif";
		}
		else if (Image.__isWebP(data))
		{
			type = "image/webp";
		}

		IS_SELECT = false;

		var bytes:Bytes = data;
		var path:String = defaultPath == null ? null : Path.directory(defaultPath);
		var defaultName:String = defaultPath == null ? null : Path.withoutDirectory(defaultPath);

		JNI.callMember(JNI.createMemberMethod('org/haxe/lime/FileDialog', 'save',
			'([BLjava/lang/String;Ljava/lang/String;Ljava/lang/String;)V'),
			JNI_FILE_DIALOG, [bytes == null ? null : bytes.getData(), type, path, defaultName]);

		return true;

		#elseif ios
		isBrowseSave = false;

		var titleStr = defaultPath != null ? Path.withoutDirectory(defaultPath) : (title != null ? title : "untitled");
		var tempPath = System.documentsDirectory + "/" + titleStr;

		sys.io.File.saveBytes(tempPath, data);

		NativeCFFI.lime_file_dialog_save_ios(native_id, tempPath);
		return true;

		#else
		onCancel.dispatch();
		return false;
		#end
	}

	/* ------------------------------------------------------------------------
		Internal helpers
	------------------------------------------------------------------------ */

	@:noCompletion
	private static function __applySaveFilterExtension(path:String, filter:FileDialogFilter):String
	{
		if (path == null)
		{
			return null;
		}

		if (!Path.isAbsolute(path)
			|| filter == null
			|| (filter.pattern == null || filter.pattern.length == 0)
			|| (filter.pattern != null && filter.pattern == '*'))
		{
			return path;
		}

		var extension:String = Path.extension(path);
		var patterns:Array<String> = filter.pattern.split(';');

		var extensionLower:String = extension.toLowerCase();
		var patternsLower:Array<String> = patterns.map(f -> f.toLowerCase());

		if (patterns.length == 1 || extension.length == 0 || !patternsLower.contains(extensionLower))
		{
			path = Path.withExtension(path, patterns[0]);
		}

		return path;
	}

	@:noCompletion
	private static function __filterFromString(filter:String):Array<FileDialogFilter>
	{
		if (filter == null || filter.length == 0)
		{
			return null;
		}

		var parts:Array<String> = filter.split(",");
		var patterns:Array<String> = [];

		for (part in parts)
		{
			var p = StringTools.trim(part);

			if (p.startsWith("*."))
			{
				p = p.substring(2);
			}
			else if (p.startsWith("."))
			{
				p = p.substring(1);
			}
			else if (p.startsWith("*"))
			{
				p = p.substring(1);
			}

			if (p.length > 0 && p != "*" && !patterns.contains(p))
			{
				patterns.push(p);
			}
		}

		if (patterns.length == 0)
		{
			return null;
		}

		return [new FileDialogFilter(filter, patterns.join(";"))];
	}

	@:noCompletion
	private static function __filterToString(filters:Array<FileDialogFilter>):String
	{
		if (filters == null || filters.length == 0)
		{
			return null;
		}

		var extensions:Array<String> = [];

		for (filter in filters)
		{
			if (filter == null || filter.pattern == null || filter.pattern.length == 0)
			{
				continue;
			}

			var parts:Array<String> = filter.pattern.split(";");

			for (part in parts)
			{
				var p = StringTools.trim(part);

				if (p.startsWith("*."))
				{
					p = p.substring(2);
				}
				else if (p.startsWith("."))
				{
					p = p.substring(1);
				}
				else if (p.startsWith("*"))
				{
					p = p.substring(1);
				}

				if (p.length > 0 && p != "*" && !extensions.contains(p))
				{
					extensions.push(p);
				}
			}
		}

		return extensions.length > 0 ? extensions.join(",") : null;
	}

	@:noCompletion
	private static function __splitPaths(path:String):Array<String>
	{
		if (path == null || path.length == 0)
		{
			return [];
		}

		var separator:String = null;

		if (path.indexOf("\n") >= 0)
		{
			separator = "\n";
		}
		else if (path.indexOf(",") >= 0)
		{
			// Legacy compatibility. New code prefers "\n".
			separator = ",";
		}

		if (separator == null)
		{
			return [path];
		}

		var result:Array<String> = [];

		for (part in path.split(separator))
		{
			if (part != null && part.length > 0)
			{
				result.push(part);
			}
		}

		return result;
	}

	#if (android || ios)
	@:noCompletion
	private static function __clearDialog(dialog:FileDialog):Void
	{
		// Best effort cleanup. If your lime.app.Event version does not have clear(),
		// remove these calls; the dialog will still be garbage collected eventually.
		try dialog.onCancel.clear(); catch (_:Dynamic) {}
		try dialog.onOpen.clear(); catch (_:Dynamic) {}
		try dialog.onSave.clear(); catch (_:Dynamic) {}
		try dialog.onSelect.clear(); catch (_:Dynamic) {}
		try dialog.onSelectMultiple.clear(); catch (_:Dynamic) {}
	}

	@:noCompletion
	private static function __mobileOpenFile(title:String, callback:Array<String>->FileDialogFilter->Void,
			filters:Array<FileDialogFilter>, defaultPath:String, allowMultiple:Bool):Void
	{
		var dialog = new FileDialog();
		var done = false;

		var finish = function(paths:Array<String>):Void
		{
			if (done) return;
			done = true;

			__clearDialog(dialog);

			if (callback != null)
			{
				callback(paths != null ? paths : [], null);
			}
		};

		dialog.onSelect.add(function(path:String)
		{
			finish([path]);
		});

		dialog.onSelectMultiple.add(function(paths:Array<String>)
		{
			finish(paths);
		});

		dialog.onCancel.add(function()
		{
			finish([]);
		});

		var type:FileDialogType = allowMultiple ? OPEN_MULTIPLE : OPEN;
		dialog.browse(type, __filterToString(filters), defaultPath, title);
	}

	@:noCompletion
	private static function __mobileOpenDirectory(title:String, callback:Array<String>->Void,
			defaultPath:String, allowMultiple:Bool):Void
	{
		var dialog = new FileDialog();
		var done = false;

		var finish = function(paths:Array<String>):Void
		{
			if (done) return;
			done = true;

			__clearDialog(dialog);

			if (callback != null)
			{
				callback(paths != null ? paths : []);
			}
		};

		dialog.onSelect.add(function(path:String)
		{
			finish([path]);
		});

		dialog.onSelectMultiple.add(function(paths:Array<String>)
		{
			finish(paths);
		});

		dialog.onCancel.add(function()
		{
			finish([]);
		});

		dialog.browse(OPEN_DIRECTORY, null, defaultPath, title);
	}

	@:noCompletion
	private static function __mobileSaveFile(title:String, callback:String->FileDialogFilter->Void,
			filters:Array<FileDialogFilter>, defaultPath:String):Void
	{
		var dialog = new FileDialog();
		var done = false;

		var finish = function(path:String):Void
		{
			if (done) return;
			done = true;

			__clearDialog(dialog);

			if (callback != null)
			{
				callback(path, null);
			}
		};

		dialog.onSelect.add(function(path:String)
		{
			finish(path);
		});

		dialog.onSave.add(function(path:String)
		{
			finish(path);
		});

		dialog.onCancel.add(function()
		{
			finish(null);
		});

		dialog.browse(SAVE, __filterToString(filters), defaultPath, title);
	}
	#end

	#if android
	@:runOnMainThread
	@:keep
	private function onJNIActivityResult(requestCode:Int, resultCode:Int, uri:String, path:String)
	{
		if (resultCode != RESULT_OK)
		{
			onCancel.dispatch();
			IS_SELECT = false;
			return;
		}

		if (path == null) path = uri;
		if (path == null)
		{
			onCancel.dispatch();
			IS_SELECT = false;
			return;
		}

		switch (requestCode)
		{
			case OPEN_REQUEST_CODE:
				try
				{
					if (IS_SELECT)
					{
						onSelect.dispatch(path);
					}
					else
					{
						onOpen.dispatch(File.getBytes(path));
					}
				}
				catch (e:Dynamic)
				{
					if (IS_SELECT)
						trace('Failed to dispatch onSelect: $e');
					else
						trace('Failed to dispatch onOpen: $e');
				}

			case OPEN_MULTIPLE_REQUEST_CODE:
				try
				{
					var paths:Array<String> = __splitPaths(path);

					if (paths == null || paths.length <= 0)
					{
						throw "Got empty paths array";
					}

					if (IS_SELECT)
					{
						onSelectMultiple.dispatch(paths);
					}
					else
					{
						// Legacy open() does not support multiple, but be defensive.
						onOpen.dispatch(File.getBytes(paths[0]));
					}
				}
				catch (e:Dynamic)
				{
					trace('Failed to dispatch OPEN_MULTIPLE result: $e');
				}

			case SAVE_REQUEST_CODE:
				try
				{
					if (IS_SELECT)
					{
						onSelect.dispatch(path);
					}
					else
					{
						onSave.dispatch(path);
					}
				}
				catch (e:Dynamic)
				{
					if (IS_SELECT)
						trace('Failed to dispatch onSelect: $e');
					else
						trace('Failed to dispatch onSave: $e');
				}

			case DOCUMENT_TREE_REQUEST_CODE:
				try
				{
					onSelect.dispatch(path);
				}
				catch (e:Dynamic)
				{
					trace('Failed to dispatch document tree result: $e');
				}
		}

		IS_SELECT = false;
	}
	#end
}

#if ios
@:access(lime._internal.backend.native.NativeCFFI)
@:access(lime.ui.FileDialog)
private class FileDialogEventHanlder
{
	public var fileDialogEventInfo:FileDialogEventInfo;

	public function new()
	{
		fileDialogEventInfo = new FileDialogEventInfo(FILE_DIALOG_EVENT, "", -1);
		NativeCFFI.lime_file_dialog_manager_register_ios(handleFileDialogEvent, fileDialogEventInfo);
	}

	private function handleFileDialogEvent():Void
	{
		if (!FileDialog.fileDialogInstances.exists(fileDialogEventInfo.id)) return;

		var fileDialogInstance = FileDialog.fileDialogInstances.get(fileDialogEventInfo.id);
		var file:String = fileDialogEventInfo.file;

		switch (fileDialogEventInfo.type)
		{
			case FILE_OPEN_SUCCESS:
				try
				{
					fileDialogInstance.onOpen.dispatch(sys.io.File.getBytes(file));
				}
				catch (e:Dynamic)
				{
					fileDialogInstance.onCancel.dispatch();
				}

			case FILE_BROWSE_SELECT:
				fileDialogInstance.onSelect.dispatch(file);

			case FILE_BROWSE_SELECT_MULTIPLE:
				fileDialogInstance.onSelectMultiple.dispatch(FileDialog.__splitPaths(file));

			case FILE_SAVE_SUCCESS:
				if (fileDialogInstance.isBrowseSave)
				{
					fileDialogInstance.onSelect.dispatch(file);
				}
				else
				{
					fileDialogInstance.onSave.dispatch(file);
				}

			case FILE_OPEN_ERROR | FILE_OPEN_CANCELED | FILE_SAVE_CANCELED | FILE_SAVE_ERROR:
				fileDialogInstance.onCancel.dispatch();

			default:
		}
	}
}

@:keep
private class FileDialogEventInfo
{
	public var id:Int;
	public var file:String;
	public var type:FileDialogEventType;

	public function new(type:FileDialogEventType = null, file:String = "", id:Int = -1)
	{
		this.type = type;
		this.file = file;
		this.id = id;
	}

	public function clone():FileDialogEventInfo
	{
		return new FileDialogEventInfo(type, file, id);
	}
}

#if (haxe_ver >= 4.0) private enum #else @:enum private #end abstract FileDialogEventType(Int)
{
	var FILE_OPEN_SUCCESS = 0;
	var FILE_OPEN_CANCELED = 1;
	var FILE_OPEN_ERROR = 2;
	var FILE_BROWSE_SELECT = 3;
	var FILE_BROWSE_SELECT_MULTIPLE = 4;
	var FILE_SAVE_SUCCESS = 5;
	var FILE_SAVE_CANCELED = 6;
	var FILE_SAVE_ERROR = 7;
	var FILE_DIALOG_EVENT = 8;
}
#end