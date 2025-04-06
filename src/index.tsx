import { NativeModules, Platform, NativeEventEmitter } from 'react-native';

const LINKING_ERROR =
  `The package 'react-native-ftp-service' doesn't seem to be linked. Make sure: \n\n` +
  Platform.select({ ios: "- You have run 'pod install'\n", default: '' }) +
  '- You rebuilt the app after installing the package\n' +
  '- You are not using Expo Go\n';

const FtpService = NativeModules.FtpService
  ? NativeModules.FtpService
  : new Proxy(
      {},
      {
        get() {
          throw new Error(LINKING_ERROR);
        },
      }
    );

// Create event emitter for progress events
const eventEmitter = new NativeEventEmitter(FtpService);

// Token type để xác định nhiệm vụ upload/download
export type TaskToken = string;

export interface FileInfo {
  name: string;
  type: 'file' | 'directory' | 'dir' | 'link' | 'unknown';
  size: number;
  timestamp: string;
}

export interface ProgressInfo {
  token: string;
  percentage: number;
}

// Progress listener type
export type ProgressListener = (info: ProgressInfo) => void;

// Map to store progress listeners
const progressListeners: Set<ProgressListener> = new Set();

// Setup the event listener
eventEmitter.addListener('Progress', (event: ProgressInfo) => {
  // Notify all registered listeners
  progressListeners.forEach((listener) => listener(event));
});

/**
 * Add a progress listener for upload/download operations
 * @param listener Function to call with progress updates
 * @returns Function to remove the listener
 */
export function addProgressListener(listener: ProgressListener): () => void {
  progressListeners.add(listener);

  // Return function to remove the listener
  return () => {
    progressListeners.delete(listener);
  };
}

// Biến để lưu thông tin kết nối hiện tại
let _currentHost: string = '';
let _currentPort: number = 21;
let _currentUsername: string = '';
let _currentPassword: string = '';

/**
 * Setup connection to an FTP server
 * @param host The FTP server hostname or IP address
 * @param port The FTP server port (default: 21)
 * @param username The username
 * @param password The password
 * @returns A promise that resolves when setup is complete
 */
export function setup(
  host: string,
  port: number = 21,
  username: string,
  password: string
): Promise<boolean> {
  return FtpService.setup(host, port, username, password);
}

/**
 * Connect to an FTP server
 * @param host The FTP server hostname or IP address
 * @param port The FTP server port (default: 21)
 * @returns A promise that resolves when connected
 */
export function connect(host: string, port: number = 21): Promise<string> {
  // Lưu trữ tạm thời các thông tin kết nối để sử dụng sau
  _currentHost = host;
  _currentPort = port;

  // Nếu người dùng đã đăng nhập trước đó, thiết lập lại kết nối
  if (_currentUsername && _currentPassword) {
    return setup(host, port, _currentUsername, _currentPassword).then(
      () => 'Connected successfully'
    );
  }

  return Promise.resolve('Connection info stored, call login() next');
}

/**
 * Login to the FTP server
 * @param username The username
 * @param password The password
 * @returns A promise that resolves when logged in
 */
export function login(username: string, password: string): Promise<string> {
  _currentUsername = username;
  _currentPassword = password;

  // Nếu đã gọi connect trước đó
  if (_currentHost) {
    return setup(_currentHost, _currentPort, username, password).then(
      () => 'Login successful'
    );
  }

  return Promise.resolve('Login info stored, call connect() first');
}

/**
 * List files in a directory
 * @param directory The directory path
 * @returns A promise that resolves with an array of FileInfo objects
 */
export function listFiles(directory: string): Promise<FileInfo[]> {
  return FtpService.list(directory);
}

/**
 * Upload a file to the FTP server
 * @param localPath The local file path
 * @param remotePath The remote file path
 * @returns A promise that resolves to true when the file is uploaded successfully
 */
export function uploadFile(
  localPath: string,
  remotePath: string
): Promise<boolean> {
  return FtpService.uploadFile(localPath, remotePath);
}

/**
 * Cancel an upload that is in progress
 * @param token The upload token to cancel
 * @returns A promise that resolves to true if canceled successfully
 */
export function cancelUploadFile(token: TaskToken): Promise<boolean> {
  return FtpService.cancelUploadFile(token);
}

/**
 * Download a file from the FTP server
 * @param localPath The local file path where the file will be saved
 * @param remotePath The remote file path to download
 * @returns A promise that resolves to true when the file is downloaded successfully
 */
export function downloadFile(
  localPath: string,
  remotePath: string
): Promise<boolean> {
  return FtpService.downloadFile(localPath, remotePath);
}

/**
 * Cancel a download that is in progress
 * @param token The download token to cancel
 * @returns A promise that resolves to true if canceled successfully
 */
export function cancelDownloadFile(token: TaskToken): Promise<boolean> {
  return FtpService.cancelDownloadFile(token);
}

/**
 * Remove a file or directory from the FTP server
 * @param path The path to remove (appends "/" for directories)
 * @returns A promise that resolves to true when removed successfully
 */
export function remove(path: string): Promise<boolean> {
  return FtpService.remove(path);
}

/**
 * Delete a file from the FTP server (alias for remove)
 * @param path The file path
 * @returns A promise that resolves when the file is deleted
 */
export function deleteFile(path: string): Promise<boolean> {
  return remove(path);
}

/**
 * Delete a directory from the FTP server (alias for remove)
 * @param path The directory path
 * @returns A promise that resolves when the directory is deleted
 */
export function deleteDirectory(path: string): Promise<boolean> {
  // Ensure path ends with / for directory
  const dirPath = path.endsWith('/') ? path : `${path}/`;
  return remove(dirPath);
}

/**
 * Create a new directory on the FTP server
 * @param path The directory path to create
 * @returns A promise that resolves to true when the directory is created successfully
 */
export function makeDirectory(path: string): Promise<boolean> {
  return FtpService.makeDirectory(path);
}

/**
 * Rename a file or directory on the FTP server
 * @param oldPath The current path of the file or directory
 * @param newPath The new path for the file or directory
 * @returns A promise that resolves to true when renamed successfully
 */
export function rename(oldPath: string, newPath: string): Promise<boolean> {
  return FtpService.rename(oldPath, newPath);
}

/**
 * Make sure token is properly formatted for tracking progress
 * @param localPath Local file path
 * @param remotePath Remote file path
 * @param isDownload Whether this is a download operation
 * @returns Properly formatted token
 */
export function makeProgressToken(
  localPath: string,
  remotePath: string,
  isDownload: boolean = false
): TaskToken {
  if (isDownload) {
    return `${localPath}<=${remotePath}`;
  }
  return `${localPath}=>${remotePath}`;
}

export default {
  connect,
  login,
  listFiles,
  uploadFile,
  cancelUploadFile,
  downloadFile,
  cancelDownloadFile,
  remove,
  deleteFile,
  deleteDirectory,
  addProgressListener,
  setup,
  makeProgressToken,
  makeDirectory,
  rename,
};
