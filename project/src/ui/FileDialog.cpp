#include <ui/FileDialog.h>

#if defined(LIME_SDL) \
	&& !defined(ANDROID) \
	&& !defined(IPHONE) \
	&& !defined(IPHONEOS) \
	&& !defined(HX_IOS) \
	&& (defined(HX_WINDOWS) || defined(HX_LINUX) || (defined(HX_MACOS) && !defined(HX_IOS)))

	#define LIME_FILE_DIALOG_SDL3_DESKTOP 1

	#include "../backend/sdl/SDLWindow.h"
	#include <SDL3/SDL.h>

	#if __has_include(<SDL3/SDL_filedialog.h>)
		#include <SDL3/SDL_filedialog.h>
	#elif __has_include(<SDL3/SDL_dialog.h>)
		#include <SDL3/SDL_dialog.h>
	#endif

	#if defined(SDL_PROP_FILE_DIALOG_WINDOW_POINTER)
		#define LIME_FILE_DIALOG_SDL3_IMPL 1
	#endif

#endif

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <vector>
#include <string>
#include <functional>


namespace lime {


	#ifdef LIME_FILE_DIALOG_SDL3_IMPL

	struct FileDialogData
	{
		std::function<void(const char* const*, int, int)> callback;
		std::vector<SDL_DialogFileFilter> filters;
	};


	struct MainThreadCallbackData
	{
		const char** filelist;
		int filecount;
		int filter;
		FileDialogData* dialogData;
	};


	static void FreeFilters(std::vector<SDL_DialogFileFilter>& filters)
	{
		for (auto& f : filters)
		{
			if (f.name != nullptr)
			{
				SDL_free((void*)f.name);
				f.name = nullptr;
			}

			if (f.pattern != nullptr)
			{
				SDL_free((void*)f.pattern);
				f.pattern = nullptr;
			}
		}

		filters.clear();
	}


	static void FreeFilelist(const char** filelist, int filecount)
	{
		if (filelist != nullptr)
		{
			for (int i = 0; i < filecount; ++i)
			{
				if (filelist[i] != nullptr)
				{
					SDL_free((void*)filelist[i]);
				}
			}

			SDL_free((void*)filelist);
		}
	}


	static void CleanupDialogData(FileDialogData* data)
	{
		if (data != nullptr)
		{
			FreeFilters(data->filters);
			delete data;
		}
	}


	static void CleanupMainThreadData(MainThreadCallbackData* mainData)
	{
		if (mainData != nullptr)
		{
			FreeFilelist(mainData->filelist, mainData->filecount);
			CleanupDialogData(mainData->dialogData);
			delete mainData;
		}
	}


	static void SDLCALL mainThreadCallback(void* userdata)
	{
		auto* mainData = static_cast<MainThreadCallbackData*>(userdata);

		if (mainData == nullptr)
		{
			return;
		}

		auto* data = mainData->dialogData;

		if (data != nullptr)
		{
			if (data->callback)
			{
				data->callback(mainData->filelist, mainData->filecount, mainData->filter);
			}

			FreeFilters(data->filters);
			delete data;
		}

		FreeFilelist(mainData->filelist, mainData->filecount);
		delete mainData;
	}


	static void SDLCALL dialogFileCallbackThunk(void* userdata, const char* const* filelist, int filter)
	{
		auto* data = static_cast<FileDialogData*>(userdata);

		if (data == nullptr)
		{
			return;
		}

		int filecount = 0;

		if (filelist != nullptr && filelist[0] != nullptr)
		{
			while (filelist[filecount] != nullptr)
			{
				filecount++;
			}
		}

		auto* mainData = new MainThreadCallbackData;

		mainData->filecount = filecount;
		mainData->filter = filter;
		mainData->dialogData = data;
		mainData->filelist = nullptr;

		if (filecount > 0 && filelist != nullptr)
		{
			mainData->filelist = static_cast<const char**>(SDL_malloc((filecount + 1) * sizeof(const char*)));

			if (mainData->filelist == nullptr)
			{
				mainData->filecount = 0;
			}
			else
			{
				for (int i = 0; i < filecount; ++i)
				{
					mainData->filelist[i] = SDL_strdup(filelist[i]);
				}

				mainData->filelist[filecount] = nullptr;
			}
		}

		if (!SDL_RunOnMainThread(mainThreadCallback, mainData, false))
		{
			CleanupMainThreadData(mainData);
		}
	}


	static std::vector<SDL_DialogFileFilter> buildFilters(const char** names, const char** patterns, int count)
	{
		std::vector<SDL_DialogFileFilter> filters;

		if (count <= 0)
		{
			return filters;
		}

		filters.reserve(count);

		for (int i = 0; i < count; ++i)
		{
			SDL_DialogFileFilter f;
			f.name = SDL_strdup(names != nullptr && names[i] != nullptr ? names[i] : "");
			f.pattern = SDL_strdup(patterns != nullptr && patterns[i] != nullptr ? patterns[i] : "*");
			filters.push_back(f);
		}

		return filters;
	}

	#endif


	void FileDialog::OpenDirectory(
		Window* window,
		const char* title,
		std::function<void(const char* const*, int, int)> callback,
		const char* defaultPath,
		bool allowMultiple
	)
	{
		#ifdef LIME_FILE_DIALOG_SDL3_IMPL

		SDL_PropertiesID props = SDL_CreateProperties();

		if (props == 0)
		{
			if (callback)
			{
				callback(nullptr, 0, -1);
			}

			return;
		}

		SDL_SetPointerProperty(
			props,
			SDL_PROP_FILE_DIALOG_WINDOW_POINTER,
			window != nullptr ? static_cast<SDLWindow*>(window)->sdlWindow : nullptr
		);

		if (defaultPath != nullptr)
		{
			SDL_SetStringProperty(props, SDL_PROP_FILE_DIALOG_LOCATION_STRING, defaultPath);
		}

		SDL_SetBooleanProperty(props, SDL_PROP_FILE_DIALOG_MANY_BOOLEAN, allowMultiple);

		if (title != nullptr)
		{
			SDL_SetStringProperty(props, SDL_PROP_FILE_DIALOG_TITLE_STRING, title);
		}

		auto* dialogData = new FileDialogData;
		dialogData->callback = std::move(callback);

		bool shown = SDL_ShowFileDialogWithProperties(
			SDL_FILEDIALOG_OPENFOLDER,
			dialogFileCallbackThunk,
			dialogData,
			props
		);

		if (!shown)
		{
			if (dialogData->callback)
			{
				dialogData->callback(nullptr, 0, -1);
			}

			CleanupDialogData(dialogData);
		}

		SDL_DestroyProperties(props);

		#else

		if (callback)
		{
			callback(nullptr, 0, -1);
		}

		#endif
	}


	void FileDialog::OpenFile(
		Window* window,
		const char* title,
		std::function<void(const char* const*, int, int)> callback,
		const char** names,
		const char** patterns,
		int filterCount,
		const char* defaultPath,
		bool allowMultiple
	)
	{
		#ifdef LIME_FILE_DIALOG_SDL3_IMPL

		auto* dialogData = new FileDialogData;
		dialogData->callback = std::move(callback);
		dialogData->filters = buildFilters(names, patterns, filterCount);

		SDL_PropertiesID props = SDL_CreateProperties();

		if (props == 0)
		{
			FreeFilters(dialogData->filters);

			if (dialogData->callback)
			{
				dialogData->callback(nullptr, 0, -1);
			}

			delete dialogData;
			return;
		}

		if (!dialogData->filters.empty())
		{
			SDL_SetPointerProperty(
				props,
				SDL_PROP_FILE_DIALOG_FILTERS_POINTER,
				(void*)dialogData->filters.data()
			);

			SDL_SetNumberProperty(
				props,
				SDL_PROP_FILE_DIALOG_NFILTERS_NUMBER,
				static_cast<Sint64>(dialogData->filters.size())
			);
		}

		SDL_SetPointerProperty(
			props,
			SDL_PROP_FILE_DIALOG_WINDOW_POINTER,
			window != nullptr ? static_cast<SDLWindow*>(window)->sdlWindow : nullptr
		);

		if (defaultPath != nullptr)
		{
			SDL_SetStringProperty(props, SDL_PROP_FILE_DIALOG_LOCATION_STRING, defaultPath);
		}

		SDL_SetBooleanProperty(props, SDL_PROP_FILE_DIALOG_MANY_BOOLEAN, allowMultiple);

		if (title != nullptr)
		{
			SDL_SetStringProperty(props, SDL_PROP_FILE_DIALOG_TITLE_STRING, title);
		}

		bool shown = SDL_ShowFileDialogWithProperties(
			SDL_FILEDIALOG_OPENFILE,
			dialogFileCallbackThunk,
			dialogData,
			props
		);

		if (!shown)
		{
			FreeFilters(dialogData->filters);

			if (dialogData->callback)
			{
				dialogData->callback(nullptr, 0, -1);
			}

			delete dialogData;
		}

		SDL_DestroyProperties(props);

		#else

		if (callback)
		{
			callback(nullptr, 0, -1);
		}

		#endif
	}


	void FileDialog::SaveFile(
		Window* window,
		const char* title,
		std::function<void(const char* const*, int, int)> callback,
		const char** names,
		const char** patterns,
		int filterCount,
		const char* defaultPath
	)
	{
		#ifdef LIME_FILE_DIALOG_SDL3_IMPL

		auto* dialogData = new FileDialogData;
		dialogData->callback = std::move(callback);
		dialogData->filters = buildFilters(names, patterns, filterCount);

		SDL_PropertiesID props = SDL_CreateProperties();

		if (props == 0)
		{
			FreeFilters(dialogData->filters);

			if (dialogData->callback)
			{
				dialogData->callback(nullptr, 0, -1);
			}

			delete dialogData;
			return;
		}

		if (!dialogData->filters.empty())
		{
			SDL_SetPointerProperty(
				props,
				SDL_PROP_FILE_DIALOG_FILTERS_POINTER,
				(void*)dialogData->filters.data()
			);

			SDL_SetNumberProperty(
				props,
				SDL_PROP_FILE_DIALOG_NFILTERS_NUMBER,
				static_cast<Sint64>(dialogData->filters.size())
			);
		}

		SDL_SetPointerProperty(
			props,
			SDL_PROP_FILE_DIALOG_WINDOW_POINTER,
			window != nullptr ? static_cast<SDLWindow*>(window)->sdlWindow : nullptr
		);

		if (defaultPath != nullptr)
		{
			SDL_SetStringProperty(props, SDL_PROP_FILE_DIALOG_LOCATION_STRING, defaultPath);
		}

		if (title != nullptr)
		{
			SDL_SetStringProperty(props, SDL_PROP_FILE_DIALOG_TITLE_STRING, title);
		}

		bool shown = SDL_ShowFileDialogWithProperties(
			SDL_FILEDIALOG_SAVEFILE,
			dialogFileCallbackThunk,
			dialogData,
			props
		);

		if (!shown)
		{
			FreeFilters(dialogData->filters);

			if (dialogData->callback)
			{
				dialogData->callback(nullptr, 0, -1);
			}

			delete dialogData;
		}

		SDL_DestroyProperties(props);

		#else

		if (callback)
		{
			callback(nullptr, 0, -1);
		}

		#endif
	}


}