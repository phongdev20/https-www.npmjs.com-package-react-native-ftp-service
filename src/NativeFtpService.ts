// import type { TurboModule } from 'react-native';
// import { TurboModuleRegistry } from 'react-native';

// export interface FileInfo {
//   name: string;
//   size: number;
//   timestamp: string;
//   type: string;
// }

// export interface Spec extends TurboModule {
//   // Event emitter methods
//   addListener(eventName: string): void;
//   removeListeners(count: number): void;

//   setup(
//     host: string,
//     port: number,
//     username: string,
//     password: string
//   ): Promise<boolean>;
//   list(directory: string): Promise<FileInfo[]>;
//   uploadFile(localPath: string, remotePath: string): Promise<boolean>;
//   downloadFile(localPath: string, remotePath: string): Promise<boolean>;
//   cancelUploadFile(token: string): Promise<boolean>;
//   cancelDownloadFile(token: string): Promise<boolean>;
//   remove(path: string): Promise<boolean>;
//   makeDirectory(path: string): Promise<boolean>;
//   rename(oldPath: string, newPath: string): Promise<boolean>;
// }

// export default TurboModuleRegistry.getEnforcing<Spec>('FtpService');

import { NativeModules } from 'react-native';

export interface FileInfo {
  name: string;
  size: number;
  timestamp: string;
  type: string;
}

export interface SpecIOS {
  // Event emitter methods
  addListener(eventName: string): void;
  removeListeners(count: number): void;

  setup(
    host: string,
    port: number,
    username: string,
    password: string
  ): Promise<boolean>;
  list(directory: string): Promise<FileInfo[]>;
  uploadFile(localPath: string, remotePath: string): Promise<boolean>;
  downloadFile(localPath: string, remotePath: string): Promise<boolean>;
  cancelUploadFile(token: string): Promise<boolean>;
  cancelDownloadFile(token: string): Promise<boolean>;
  remove(path: string): Promise<boolean>;
  makeDirectory(path: string): Promise<boolean>;
  rename(oldPath: string, newPath: string): Promise<boolean>;
}
const FtpService = NativeModules.FtpService as SpecIOS;

export default FtpService;

// import { NativeModules, Platform } from 'react-native';
// import type { TurboModule } from 'react-native';
// import { TurboModuleRegistry } from 'react-native';

// export interface FileInfo {
//   name: string;
//   size: number;
//   timestamp: string;
//   type: string;
// }

// export interface Spec extends TurboModule {
//   // Event emitter methods
//   addListener(eventName: string): void;
//   removeListeners(count: number): void;

//   setup(
//     host: string,
//     port: number,
//     username: string,
//     password: string
//   ): Promise<boolean>;
//   list(directory: string): Promise<FileInfo[]>;
//   uploadFile(localPath: string, remotePath: string): Promise<boolean>;
//   downloadFile(localPath: string, remotePath: string): Promise<boolean>;
//   cancelUploadFile(token: string): Promise<boolean>;
//   cancelDownloadFile(token: string): Promise<boolean>;
//   remove(path: string): Promise<boolean>;
//   makeDirectory(path: string): Promise<boolean>;
//   rename(oldPath: string, newPath: string): Promise<boolean>;
// }

// export interface SpecIOS {
//   // Event emitter methods
//   addListener(eventName: string): void;
//   removeListeners(count: number): void;

//   setup(
//     host: string,
//     port: number,
//     username: string,
//     password: string
//   ): Promise<boolean>;
//   list(directory: string): Promise<FileInfo[]>;
//   uploadFile(localPath: string, remotePath: string): Promise<boolean>;
//   downloadFile(localPath: string, remotePath: string): Promise<boolean>;
//   cancelUploadFile(token: string): Promise<boolean>;
//   cancelDownloadFile(token: string): Promise<boolean>;
//   remove(path: string): Promise<boolean>;
//   makeDirectory(path: string): Promise<boolean>;
//   rename(oldPath: string, newPath: string): Promise<boolean>;
// }

// // For Android, use TurboModule
// const FtpServiceAndroid = TurboModuleRegistry.getEnforcing<Spec>('FtpService');

// // For iOS, use NativeModules
// const FtpServiceIOS = NativeModules.FtpService as SpecIOS;

// // Platform-specific selection
// const FtpService =
//   Platform.OS === 'android' ? FtpServiceAndroid : FtpServiceIOS;

// export default FtpService;
