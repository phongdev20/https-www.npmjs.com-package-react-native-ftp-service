package com.ftpservice

import android.util.Log
import androidx.annotation.Nullable
import com.facebook.react.bridge.*
import com.facebook.react.modules.core.DeviceEventManagerModule
import org.apache.commons.net.ftp.FTP
import org.apache.commons.net.ftp.FTPClient
import org.apache.commons.net.ftp.FTPFile
import java.io.*
import java.text.SimpleDateFormat
import java.util.*

class FtpServiceModule(private val reactContext: ReactApplicationContext) : 
    ReactContextBaseJavaModule(reactContext) {

    private val TAG = "FtpService"
    private lateinit var ipAddress: String
    private var port: Int = 0
    private lateinit var username: String
    private lateinit var password: String
    private val uploadingTasks = HashMap<String, Thread>()
    private val downloadingTasks = HashMap<String, Thread>()

    override fun getName(): String {
        return "FtpService"
    }

    companion object {
        private const val MAX_UPLOAD_COUNT = 10
        private const val MAX_DOWNLOAD_COUNT = 10
        private const val RNFTPCLIENT_PROGRESS_EVENT_NAME = "Progress"
        private const val RNFTPCLIENT_ERROR_CODE_LOGIN = "RNFTPCLIENT_ERROR_CODE_LOGIN"
        private const val RNFTPCLIENT_ERROR_CODE_LIST = "RNFTPCLIENT_ERROR_CODE_LIST"
        private const val RNFTPCLIENT_ERROR_CODE_UPLOAD = "RNFTPCLIENT_ERROR_CODE_UPLOAD"
        private const val RNFTPCLIENT_ERROR_CODE_CANCELUPLOAD = "RNFTPCLIENT_ERROR_CODE_CANCELUPLOAD"
        private const val RNFTPCLIENT_ERROR_CODE_REMOVE = "RNFTPCLIENT_ERROR_CODE_REMOVE"
        private const val RNFTPCLIENT_ERROR_CODE_LOGOUT = "RNFTPCLIENT_ERROR_CODE_LOGOUT"
        private const val RNFTPCLIENT_ERROR_CODE_DOWNLOAD = "RNFTPCLIENT_ERROR_CODE_DOWNLOAD"
        private const val ERROR_MESSAGE_CANCELLED = "ERROR_MESSAGE_CANCELLED"
    }

    @ReactMethod
    fun setup(ipAddress: String, port: Int, username: String, password: String, promise: Promise) {
        this.ipAddress = ipAddress
        this.port = port
        this.username = username
        this.password = password
        promise.resolve(true)
    }

    private fun login(client: FTPClient) {
        client.connect(ipAddress, port)
        client.enterLocalPassiveMode()
        client.login(username, password)
    }

    private fun logout(client: FTPClient) {
        try {
            client.logout()
        } catch (e: IOException) {
            Log.d(TAG, "logout error", e)
        }
        try {
            if (client.isConnected) {
                client.disconnect()
            }
        } catch (e: IOException) {
            Log.d(TAG, "logout disconnect error", e)
        }
    }

    private fun getStringByType(type: Int): String = when (type) {
        FTPFile.DIRECTORY_TYPE -> "dir"
        FTPFile.FILE_TYPE -> "file"
        FTPFile.SYMBOLIC_LINK_TYPE -> "link"
        else -> "unknown"
    }

    private fun ISO8601StringFromCalender(calendar: Calendar): String {
        val date = calendar.time
        val sdf = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSSXXX")
        sdf.timeZone = TimeZone.getTimeZone("CET")
        return sdf.format(date)
    }

    @ReactMethod
    fun list(path: String, promise: Promise) {
        Thread {
            val client = FTPClient()
            try {
                login(client)
                val files = client.listFiles(path)
                val arrFiles = Arguments.createArray()
                for (file in files) {
                    val tmp = Arguments.createMap()
                    tmp.putString("name", file.name)
                    tmp.putInt("size", file.size.toInt())
                    tmp.putString("timestamp", ISO8601StringFromCalender(file.timestamp))
                    tmp.putString("type", getStringByType(file.type))
                    arrFiles.pushMap(tmp)
                }
                promise.resolve(arrFiles)
            } catch (e: Exception) {
                promise.reject(RNFTPCLIENT_ERROR_CODE_LIST, e.message)
            } finally {
                logout(client)
            }
        }.start()
    }

    @ReactMethod
    fun remove(path: String, promise: Promise) {
        Thread {
            val client = FTPClient()
            try {
                login(client)
                if (path.endsWith(File.separator)) {
                    client.removeDirectory(path)
                } else {
                    client.deleteFile(path)
                }
                promise.resolve(true)
            } catch (e: IOException) {
                promise.reject("ERROR", e.message)
            } finally {
                logout(client)
            }
        }.start()
    }

    private fun makeToken(path: String, remoteDestinationDir: String): String =
        "$path=>$remoteDestinationDir"

    private fun makeDownloadToken(path: String, remoteDestinationDir: String): String =
        "$path<=$remoteDestinationDir"

    private fun sendEvent(reactContext: ReactContext, eventName: String, @Nullable params: WritableMap) {
        reactContext
            .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
            .emit(eventName, params)
    }

    private fun sendProgressEventToToken(token: String, percentage: Int) {
        val params = Arguments.createMap()
        params.putString("token", token)
        params.putInt("percentage", percentage)

        Log.d(TAG, "send progress $percentage to: $token")
        sendEvent(reactContext, RNFTPCLIENT_PROGRESS_EVENT_NAME, params)
    }

    override fun getConstants(): Map<String, Any> {
        val constants = HashMap<String, Any>()
        constants[ERROR_MESSAGE_CANCELLED] = ERROR_MESSAGE_CANCELLED
        return constants
    }

    @ReactMethod
    fun uploadFile(path: String, remoteDestinationPath: String, promise: Promise) {
        val token = makeToken(path, remoteDestinationPath)
        if (uploadingTasks.containsKey(token)) {
            promise.reject(RNFTPCLIENT_ERROR_CODE_UPLOAD, "same upload is running")
            return
        }
        if (uploadingTasks.size >= MAX_UPLOAD_COUNT) {
            promise.reject(RNFTPCLIENT_ERROR_CODE_UPLOAD, "has reached max uploading tasks")
            return
        }
        val t = Thread {
            val client = FTPClient()
            try {
                login(client)
                client.setFileType(FTP.BINARY_FILE_TYPE)
                val localFile = File(path)
                val totalBytes = localFile.length()
                var finishBytes: Long = 0

                val remoteFile = remoteDestinationPath
                val inputStream = FileInputStream(localFile)

                Log.d(TAG, "Start uploading file")

                val outputStream = client.storeFileStream(remoteFile)
                val bytesIn = ByteArray(4096)
                var read = 0

                sendProgressEventToToken(token, 0)
                Log.d(TAG, "Resolve token: $token")
                var lastPercentage = 0
                while (inputStream.read(bytesIn).also { read = it } != -1 && !Thread.currentThread().isInterrupted) {
                    outputStream.write(bytesIn, 0, read)
                    finishBytes += read
                    val newPercentage = (finishBytes * 100 / totalBytes).toInt()
                    if (newPercentage > lastPercentage) {
                        sendProgressEventToToken(token, newPercentage)
                        lastPercentage = newPercentage
                    }
                }
                inputStream.close()
                outputStream.close()
                Log.d(TAG, "Finish uploading")

                if (!Thread.currentThread().isInterrupted) {
                    val done = client.completePendingCommand()

                    if (done) {
                        promise.resolve(true)
                    } else {
                        promise.reject(RNFTPCLIENT_ERROR_CODE_UPLOAD, "${localFile.name} is not uploaded successfully.")
                        client.deleteFile(remoteFile)
                    }
                } else {
                    promise.reject(RNFTPCLIENT_ERROR_CODE_UPLOAD, ERROR_MESSAGE_CANCELLED)
                }
            } catch (e: IOException) {
                promise.reject(RNFTPCLIENT_ERROR_CODE_UPLOAD, e.message)
            } finally {
                uploadingTasks.remove(token)
                logout(client)
            }
        }
        t.start()
        uploadingTasks[token] = t
    }

    @ReactMethod
    fun cancelUploadFile(token: String, promise: Promise) {
        val upload = uploadingTasks[token]

        if (upload == null) {
            promise.reject(RNFTPCLIENT_ERROR_CODE_UPLOAD, "token is wrong")
            return
        }
        upload.interrupt()
        val client = FTPClient()
        try {
            upload.join()
            login(client)
            val remoteFile = token.split("=>")[1]
            client.deleteFile(remoteFile)
        } catch (e: Exception) {
            Log.d(TAG, "cancel upload error", e)
        } finally {
            logout(client)
        }
        uploadingTasks.remove(token)
        promise.resolve(true)
    }

    private fun getLocalFilePath(path: String, remotePath: String): String {
        return if (path.endsWith("/")) {
            val index = remotePath.lastIndexOf("/")
            path + remotePath.substring(index + 1)
        } else {
            path
        }
    }

    @Throws(Exception::class)
    private fun getRemoteSize(client: FTPClient, remoteFilePath: String): Long {
        client.sendCommand("SIZE", remoteFilePath)
        val reply = client.replyStrings
        val response = reply[0].split(" ")
        if (client.replyCode != 213) {
            throw Exception("ftp client size cmd response ${client.replyCode}")
        }
        return response[1].toLong()
    }

    @ReactMethod
    fun downloadFile(path: String, remoteDestinationPath: String, promise: Promise) {
        val token = makeDownloadToken(path, remoteDestinationPath)
        if (downloadingTasks.containsKey(token)) {
            promise.reject(RNFTPCLIENT_ERROR_CODE_DOWNLOAD, "same downloading task is running")
            return
        }
        if (downloadingTasks.size >= MAX_DOWNLOAD_COUNT) {
            promise.reject(RNFTPCLIENT_ERROR_CODE_DOWNLOAD, "has reached max downloading tasks")
            return
        }
        if (remoteDestinationPath.endsWith("/")) {
            promise.reject(RNFTPCLIENT_ERROR_CODE_DOWNLOAD, "remote path cannot be a dir")
            return
        }

        val t = Thread {
            val client = FTPClient()
            try {
                login(client)
                client.setFileType(FTP.BINARY_FILE_TYPE)

                val totalBytes = getRemoteSize(client, remoteDestinationPath)
                val downloadFile = File(getLocalFilePath(path, remoteDestinationPath))
                if (downloadFile.exists()) {
                    throw Error("local file exists: ${downloadFile.absolutePath}")
                }
                val parentDir = downloadFile.parentFile
                if (parentDir != null && !parentDir.exists()) {
                    parentDir.mkdirs()
                }
                downloadFile.createNewFile()
                var finishBytes: Long = 0

                Log.d(TAG, "Start downloading file")

                val outputStream = BufferedOutputStream(FileOutputStream(downloadFile))
                val inputStream = client.retrieveFileStream(remoteDestinationPath)
                val bytesIn = ByteArray(4096)
                var read = 0

                sendProgressEventToToken(token, 0)
                Log.d(TAG, "Resolve token: $token")
                var lastPercentage = 0

                while (inputStream.read(bytesIn).also { read = it } != -1 && !Thread.currentThread().isInterrupted) {
                    outputStream.write(bytesIn, 0, read)
                    finishBytes += read
                    val newPercentage = (finishBytes * 100 / totalBytes).toInt()
                    if (newPercentage > lastPercentage) {
                        sendProgressEventToToken(token, newPercentage)
                        lastPercentage = newPercentage
                    }
                }
                inputStream.close()
                outputStream.close()
                Log.d(TAG, "Finish downloading")

                if (!Thread.currentThread().isInterrupted) {
                    val done = client.completePendingCommand()

                    if (done) {
                        promise.resolve(true)
                    } else {
                        promise.reject(RNFTPCLIENT_ERROR_CODE_DOWNLOAD, "${downloadFile.name} is not downloaded successfully.")
                        downloadFile.delete()
                    }
                } else {
                    promise.reject(RNFTPCLIENT_ERROR_CODE_DOWNLOAD, ERROR_MESSAGE_CANCELLED)
                    downloadFile.delete()
                }
            } catch (e: Exception) {
                promise.reject(RNFTPCLIENT_ERROR_CODE_DOWNLOAD, e.message)
            } finally {
                downloadingTasks.remove(token)
                logout(client)
            }
        }
        t.start()
        downloadingTasks[token] = t
    }

    @ReactMethod
    fun cancelDownloadFile(token: String, promise: Promise) {
        val download = downloadingTasks[token]

        if (download == null) {
            promise.reject(RNFTPCLIENT_ERROR_CODE_DOWNLOAD, "token is wrong")
            return
        }
        download.interrupt()
        val client = FTPClient()
        try {
            download.join()
        } catch (e: Exception) {
            Log.d(TAG, "cancel download error", e)
        }
        downloadingTasks.remove(token)
        promise.resolve(true)
    }

    @ReactMethod
    fun makeDirectory(path: String, promise: Promise) {
        Thread {
            val client = FTPClient()
            try {
                login(client)
                val success = client.makeDirectory(path)
                if (success) {
                    promise.resolve(true)
                } else {
                    promise.reject("ERROR", "Failed to create directory: $path")
                }
            } catch (e: IOException) {
                promise.reject("ERROR", e.message)
            } finally {
                logout(client)
            }
        }.start()
    }

    @ReactMethod
    fun rename(oldPath: String, newPath: String, promise: Promise) {
        Thread {
            val client = FTPClient()
            try {
                login(client)
                val success = client.rename(oldPath, newPath)
                if (success) {
                    promise.resolve(true)
                } else {
                    promise.reject("ERROR", "Failed to rename from $oldPath to $newPath")
                }
            } catch (e: IOException) {
                promise.reject("ERROR", e.message)
            } finally {
                logout(client)
            }
        }.start()
    }

    // Alias cho phương thức list để tương thích với JS API
    @ReactMethod
    fun listFiles(path: String, promise: Promise) {
        list(path, promise)
    }

    // Thêm các phương thức cần thiết cho NativeEventEmitter
    @ReactMethod
    fun addListener(eventName: String) {
        // Phương thức này được yêu cầu bởi NativeEventEmitter
    }

    @ReactMethod
    fun removeListeners(count: Int) {
        // Phương thức này được yêu cầu bởi NativeEventEmitter
    }
}
