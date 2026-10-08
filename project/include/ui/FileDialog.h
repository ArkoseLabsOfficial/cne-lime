#ifndef LIME_UI_FILE_DIALOG_H
#define LIME_UI_FILE_DIALOG_H

#include <ui/Window.h>
#include <string>
#include <vector>
#include <functional>

#ifdef IPHONE
	#ifdef __OBJC__
		@class FileDialogObserver;
	#else
		typedef struct objc_object FileDialogObserver;
	#endif
#endif

namespace lime {

	class FileDialog {

		public:

			#ifdef IPHONE

			static int Create();
			static void Open(int id_handle);
			static void BrowseSelect(int id_handle);
			static void BrowseSelectMultiple(int id_handle);
			static void Save(int id_handle, const char* path);
			static void BrowseSave(int id_handle, const char* path);

			#else

			static void OpenDirectory(
				Window* window = nullptr,
				const char* title = nullptr,
				std::function<void(const char* const*, int, int)> callback = nullptr,
				const char* defaultPath = nullptr,
				bool allowMultiple = false
			);

			static void OpenFile(
				Window* window = nullptr,
				const char* title = nullptr,
				std::function<void(const char* const*, int, int)> callback = nullptr,
				const char** names = nullptr,
				const char** patterns = nullptr,
				int filterCount = 0,
				const char* defaultPath = nullptr,
				bool allowMultiple = false
			);

			static void SaveFile(
				Window* window = nullptr,
				const char* title = nullptr,
				std::function<void(const char* const*, int, int)> callback = nullptr,
				const char** names = nullptr,
				const char** patterns = nullptr,
				int filterCount = 0,
				const char* defaultPath = nullptr
			);

			#endif

	};

}

#endif