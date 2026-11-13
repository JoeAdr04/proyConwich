package com.example.test_code_02

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.example.test_code_02/drive_folder"
    private val folderRequestCode = 4107
    private var pendingFolderResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "pickFolder" -> pickFolder(result)
                        "checkPermission" -> {
                            val uri = call.argument<String>("uri")
                            result.success(
                                uri != null && hasWritePermission(Uri.parse(uri)),
                            )
                        }
                        "writeFile" -> {
                            val uri = call.argument<String>("uri")
                            val name = call.argument<String>("name")
                            val bytes = call.argument<ByteArray>("bytes")
                            if (uri == null || name == null || bytes == null) {
                                result.error("invalid_args", "Faltan datos.", null)
                            } else {
                                writeFile(Uri.parse(uri), name, bytes)
                                result.success(true)
                            }
                        }
                        "listFiles" -> {
                            val uri = call.argument<String>("uri")
                            if (uri == null) {
                                result.error("invalid_args", "Falta la carpeta.", null)
                            } else {
                                result.success(listFiles(Uri.parse(uri)))
                            }
                        }
                        "deleteFile" -> {
                            val uri = call.argument<String>("fileUri")
                            if (uri == null) {
                                result.error("invalid_args", "Falta el archivo.", null)
                            } else {
                                result.success(
                                    DocumentsContract.deleteDocument(
                                        contentResolver,
                                        Uri.parse(uri),
                                    ),
                                )
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error("drive_error", error.message ?: "Error de Drive.", null)
                }
            }
    }

    private fun pickFolder(result: MethodChannel.Result) {
        if (pendingFolderResult != null) {
            result.error("busy", "Ya hay un selector de carpeta abierto.", null)
            return
        }
        pendingFolderResult = result
        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(
                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION,
            )
        }
        try {
            startActivityForResult(intent, folderRequestCode)
        } catch (error: Exception) {
            pendingFolderResult = null
            result.error("drive_picker", error.message ?: "No se pudo abrir.", null)
        }
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != folderRequestCode) return
        val result = pendingFolderResult ?: return
        pendingFolderResult = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return
        }
        val takeFlags = (data?.flags ?: 0) and (
            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            )
        try {
            contentResolver.takePersistableUriPermission(uri, takeFlags)
        } catch (_: SecurityException) {
            // Si el proveedor no permite persistir, se intentará escribir igual.
        }
        result.success(
            hashMapOf(
                "uri" to uri.toString(),
                "name" to (displayName(uri) ?: "Carpeta de Drive"),
            ),
        )
    }

    private fun hasWritePermission(uri: Uri): Boolean =
        contentResolver.persistedUriPermissions.any {
            it.uri == uri && it.isWritePermission
        }

    private fun displayName(uri: Uri): String? {
        contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) {
                val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                if (index >= 0) return cursor.getString(index)
            }
        }
        return null
    }

    private fun childDocumentsUri(folderUri: Uri): Uri {
        val treeId = DocumentsContract.getTreeDocumentId(folderUri)
        return DocumentsContract.buildChildDocumentsUriUsingTree(folderUri, treeId)
    }

    private fun documentUri(folderUri: Uri, documentId: String): Uri =
        DocumentsContract.buildDocumentUriUsingTree(folderUri, documentId)

    private fun findChild(folderUri: Uri, name: String): Uri? {
        contentResolver.query(
            childDocumentsUri(folderUri),
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val display = cursor.getString(1)
                if (display == name) {
                    return documentUri(folderUri, cursor.getString(0))
                }
            }
        }
        return null
    }

    private fun writeFile(folderUri: Uri, name: String, bytes: ByteArray) {
        findChild(folderUri, name)?.let {
            DocumentsContract.deleteDocument(contentResolver, it)
        }
        val parent = documentUri(
            folderUri,
            DocumentsContract.getTreeDocumentId(folderUri),
        )
        val nuevo = DocumentsContract.createDocument(
            contentResolver,
            parent,
            "application/octet-stream",
            name,
        ) ?: throw IllegalStateException("No se pudo crear el archivo.")
        contentResolver.openOutputStream(nuevo, "w")?.use { output ->
            output.write(bytes)
            output.flush()
        } ?: throw IllegalStateException("No se pudo abrir el archivo.")
    }

    private fun listFiles(folderUri: Uri): List<Map<String, Any?>> {
        val archivos = mutableListOf<Map<String, Any?>>()
        contentResolver.query(
            childDocumentsUri(folderUri),
            arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_SIZE,
                DocumentsContract.Document.COLUMN_LAST_MODIFIED,
            ),
            null,
            null,
            null,
        )?.use { cursor ->
            while (cursor.moveToNext()) {
                val documentId = cursor.getString(0)
                archivos.add(
                    hashMapOf(
                        "uri" to documentUri(folderUri, documentId).toString(),
                        "name" to cursor.getString(1),
                        "size" to if (cursor.isNull(2)) 0 else cursor.getLong(2),
                        "modified" to if (cursor.isNull(3)) null else cursor.getLong(3),
                    ),
                )
            }
        }
        return archivos
    }
}
