package org.haxe.lime;

import android.app.Activity;
import android.content.ClipData;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Build;
import android.os.ParcelFileDescriptor;
import android.provider.DocumentsContract;
import android.provider.OpenableColumns;
import android.util.Log;
import android.webkit.MimeTypeMap;

import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.ArrayList;
import java.util.List;

import org.haxe.extension.Extension;
import org.haxe.lime.HaxeObject;

public class FileDialog extends Extension
{
	public static final String LOG_TAG = "FileDialog";

	public static final int OPEN_REQUEST_CODE = 990;
	public static final int OPEN_MULTIPLE_REQUEST_CODE = 995;
	public static final int SAVE_REQUEST_CODE = 999;
	public static final int DOCUMENT_TREE_REQUEST_CODE = 1000;

	public HaxeObject haxeObject;
	public FileSaveCallback onFileSave = null;

	// Prevent multiple FileDialog instances from dispatching each other's results.
	public boolean awaitingResults = false;

	public FileDialog(final HaxeObject haxeObject)
	{
		this.haxeObject = haxeObject;
	}

	public static FileDialog createInstance(final HaxeObject haxeObject)
	{
		return GameActivity.creatFileDialog(haxeObject);
	}

	public void open(String filter, String defaultPath, String title)
	{
		Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
		intent.addCategory(Intent.CATEGORY_OPENABLE);

		applyInitialUri(intent, defaultPath);
		applyFilters(intent, filter);

		if (title != null)
		{
			intent.putExtra(Intent.EXTRA_TITLE, title);
		}

		awaitingResults = true;
		mainActivity.startActivityForResult(intent, OPEN_REQUEST_CODE);
	}

	public void openMultiple(String filter, String defaultPath, String title)
	{
		Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
		intent.putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true);
		intent.addCategory(Intent.CATEGORY_OPENABLE);

		applyInitialUri(intent, defaultPath);
		applyFilters(intent, filter);

		if (title != null)
		{
			intent.putExtra(Intent.EXTRA_TITLE, title);
		}

		awaitingResults = true;
		mainActivity.startActivityForResult(intent, OPEN_MULTIPLE_REQUEST_CODE);
	}

	public void save(byte[] data, String mime, String defaultPath, String title)
	{
		Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
		intent.addCategory(Intent.CATEGORY_OPENABLE);

		applyInitialUri(intent, defaultPath);

		if (title != null)
		{
			intent.putExtra(Intent.EXTRA_TITLE, title);
		}

		if (data != null)
		{
			final byte[] bytes = data;

			onFileSave = new FileSaveCallback()
			{
				@Override
				public void execute(Uri uri)
				{
					writeBytesToFile(uri, bytes);
				}
			};
		}
		else
		{
			Log.w(LOG_TAG, "No bytes data were passed to `save`, no bytes will be written to it.");
		}

		if (mime == null || mime.equals("application/octet-stream"))
		{
			mime = "*/*";
		}

		intent.setType(mime);

		awaitingResults = true;
		mainActivity.startActivityForResult(intent, SAVE_REQUEST_CODE);
	}

	public void savePath(String filter, String defaultPath, String title)
	{
		Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT);
		intent.addCategory(Intent.CATEGORY_OPENABLE);

		applyInitialUri(intent, defaultPath);
		applyFilters(intent, filter);

		if (title != null)
		{
			intent.putExtra(Intent.EXTRA_TITLE, title);
		}

		onFileSave = null;

		awaitingResults = true;
		mainActivity.startActivityForResult(intent, SAVE_REQUEST_CODE);
	}

	public void openDocumentTree(String defaultPath)
	{
		Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT_TREE);
		intent.addCategory(Intent.CATEGORY_DEFAULT);

		applyInitialUri(intent, defaultPath);

		awaitingResults = true;
		mainActivity.startActivityForResult(intent, DOCUMENT_TREE_REQUEST_CODE);
	}

	public static void getPersistableURIAccess(String uriStr)
	{
		try
		{
			mainContext.getContentResolver().takePersistableUriPermission(
				Uri.parse(uriStr),
				Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_GRANT_WRITE_URI_PERMISSION
			);
		}
		catch (Exception e)
		{
			Log.e(LOG_TAG, "Failed to take persistable URI permission: " + e.getMessage());
		}
	}

	@Override
	public boolean onActivityResult(int requestCode, int resultCode, Intent data)
	{
		String uri = null;
		String path = null;

		if (haxeObject != null && awaitingResults)
		{
			if (resultCode == Activity.RESULT_OK && data != null)
			{
				Uri selected = data.getData();

				if (selected != null)
				{
					uri = selected.toString();

					switch (requestCode)
					{
						case OPEN_REQUEST_CODE:
							try
							{
								path = copyURIToCache(selected);
							}
							catch (IOException e)
							{
								Log.e(LOG_TAG, "Failed to copy file to cache: " + e.getMessage());
							}
							break;

						case OPEN_MULTIPLE_REQUEST_CODE:
							try
							{
								List<String> pathsList = new ArrayList<>();

								ClipData clipData = data.getClipData();

								if (clipData != null)
								{
									for (int i = 0; i < clipData.getItemCount(); i++)
									{
										Uri fileUri = clipData.getItemAt(i).getUri();

										if (fileUri != null)
										{
											pathsList.add(copyURIToCache(fileUri));
										}
									}
								}
								else if (selected != null)
								{
									pathsList.add(copyURIToCache(selected));
								}

								path = join(pathsList, "\n");
							}
							catch (IOException e)
							{
								Log.e(LOG_TAG, "Failed to copy files to cache: " + e.getMessage());
							}
							break;

						case SAVE_REQUEST_CODE:
							if (onFileSave != null)
							{
								onFileSave.execute(selected);
								onFileSave = null;
							}

							try
							{
								getPersistableURIAccess(uri);
							}
							catch (Exception e)
							{
								Log.e(LOG_TAG, "Failed to persist save URI: " + e.getMessage());
							}

							path = getOriginalPath(selected.getPath());
							break;

						case DOCUMENT_TREE_REQUEST_CODE:
							try
							{
								getPersistableURIAccess(uri);
							}
							catch (Exception e)
							{
								Log.e(LOG_TAG, "Failed to persist tree URI: " + e.getMessage());
							}

							path = getOriginalPath(selected.getPath());
							break;

						default:
							break;
					}
				}
				else
				{
					Log.e(LOG_TAG, "Activity result data contained no URI for request code " + requestCode);
				}
			}
			else
			{
				Log.e(LOG_TAG, "Activity results for request code " + requestCode
					+ " failed with result code " + resultCode
					+ " and data " + data);
			}
		}

		Object[] args = new Object[4];
		args[0] = requestCode;
		args[1] = resultCode;
		args[2] = uri;
		args[3] = path;

		if (haxeObject != null)
		{
			haxeObject.call("onJNIActivityResult", args);
		}

		awaitingResults = false;
		return true;
	}

	/**
	 * Attempts to convert various Android SAF/document provider paths
	 * to a more familiar, filesystem-like path (best effort conversion).
	 */
	public static String getOriginalPath(String path)
	{
		if (path == null || path.isEmpty()) return path;

		path = path.replaceFirst("/tree/primary:", "/storage/emulated/0/")
					.replaceFirst("/document/primary:", "/storage/emulated/0/")
					.replaceFirst("/document/raw:", "")
					.replaceFirst("/document/msf:", "/storage/emulated/0/Download/");

		path = path.replaceFirst("/tree/", "/storage/")
					.replaceFirst("/document/", "/storage/");

		path = path.replaceFirst(":", "/");

		return path.replace("//", "/");
	}

	public static String formatExtension(String extension)
	{
		if (extension == null) return "";

		extension = extension.trim();

		if (extension.startsWith("*."))
		{
			extension = extension.substring(2);
		}
		else if (extension.startsWith("*"))
		{
			extension = extension.substring(1);
		}
		else if (extension.startsWith("."))
		{
			extension = extension.substring(1);
		}

		return extension;
	}

	private static void applyInitialUri(Intent intent, String defaultPath)
	{
		if (defaultPath == null || defaultPath.isEmpty()) return;

		try
		{
			Uri uri;

			if (defaultPath.startsWith("content://") || defaultPath.startsWith("file://"))
			{
				uri = Uri.parse(defaultPath);
			}
			else
			{
				File file = new File(defaultPath);

				if (!file.exists()) return;

				uri = Uri.fromFile(file);
			}

			if (Build.VERSION.SDK_INT >= 26)
			{
				intent.putExtra(DocumentsContract.EXTRA_INITIAL_URI, uri);
			}
		}
		catch (Exception e)
		{
			Log.e(LOG_TAG, "Failed to apply initial URI: " + e.getMessage());
		}
	}

	private static void applyFilters(Intent intent, String filter)
	{
		if (filter == null || filter.trim().isEmpty())
		{
			intent.setType("*/*");
			return;
		}

		String[] rawFilters = filter.split(",");
		List<String> mimes = new ArrayList<>();

		for (String raw : rawFilters)
		{
			String mime = getMimeFromExtension(raw);

			if (mime != null && !mime.isEmpty() && !mimes.contains(mime))
			{
				mimes.add(mime);
			}
		}

		if (mimes.isEmpty())
		{
			intent.setType("*/*");
			return;
		}

		intent.setType(mimes.get(0));

		if (mimes.size() > 1)
		{
			intent.putExtra(Intent.EXTRA_MIME_TYPES, mimes.toArray(new String[0]));
		}
	}

	private static String getMimeFromExtension(String extension)
	{
		MimeTypeMap mimeType = MimeTypeMap.getSingleton();
		extension = formatExtension(extension);

		if (extension == null || extension.isEmpty() || extension.equals("*"))
		{
			return "*/*";
		}

		String mime = mimeType.getMimeTypeFromExtension(extension);
		return mime != null ? mime : "*/*";
	}

	private static void writeBytesToFile(Uri uri, byte[] data)
	{
		if (uri == null || data == null) return;

		try (OutputStream outputStream = mainContext.getContentResolver().openOutputStream(uri))
		{
			if (outputStream != null)
			{
				outputStream.write(data);
				outputStream.flush();
				Log.d(LOG_TAG, "File saved successfully.");
			}
		}
		catch (IOException e)
		{
			Log.e(LOG_TAG, "Failed to save file: " + e.getMessage());
		}
	}

	public static String copyURIToCache(Uri uri) throws IOException
	{
		if (uri == null) return null;

		String fileName = getDisplayName(uri);

		if (fileName == null || fileName.isEmpty())
		{
			fileName = "file_" + System.currentTimeMillis();
		}

		if (fileName.contains(":"))
		{
			fileName = fileName.split(":")[1];
		}

		File output = new File(mainContext.getCacheDir(), fileName);

		if (output.exists())
		{
			output.delete();
		}

		Log.d(LOG_TAG, "Copying URI from '" + uri + "' to cache dir: " + output.getAbsolutePath());

		try (InputStream in = mainContext.getContentResolver().openInputStream(uri);
			 OutputStream out = new FileOutputStream(output))
		{
			if (in == null)
			{
				throw new IOException("Could not open input stream for URI: " + uri);
			}

			byte[] buffer = new byte[8192];
			int read;

			while ((read = in.read(buffer)) != -1)
			{
				out.write(buffer, 0, read);
			}

			out.flush();
		}

		return output.getAbsolutePath();
	}

	private static String getDisplayName(Uri uri)
	{
		String result = null;

		try (Cursor cursor = mainContext.getContentResolver().query(
			uri,
			new String[] { OpenableColumns.DISPLAY_NAME },
			null,
			null,
			null
		))
		{
			if (cursor != null && cursor.moveToFirst())
			{
				int index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);

				if (index >= 0)
				{
					result = cursor.getString(index);
				}
			}
		}
		catch (Exception e)
		{
			Log.e(LOG_TAG, "Failed to query display name: " + e.getMessage());
		}

		if (result == null || result.isEmpty())
		{
			result = uri.getLastPathSegment();
		}

		return result;
	}

	private static String join(List<String> parts, String separator)
	{
		if (parts == null || parts.isEmpty()) return "";

		StringBuilder sb = new StringBuilder();

		for (int i = 0; i < parts.size(); i++)
		{
			if (i > 0) sb.append(separator);
			sb.append(parts.get(i));
		}

		return sb.toString();
	}
}

@FunctionalInterface
interface FileSaveCallback
{
	void execute(Uri uri);
}