import type { TurboModule } from 'react-native';
import { TurboModuleRegistry } from 'react-native';

export interface FileInfo {
  name: string;
  size: number;
  timestamp: string;
  type: string;
}

export interface Spec extends TurboModule {
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

export default TurboModuleRegistry.getEnforcing<Spec>('FtpService');
