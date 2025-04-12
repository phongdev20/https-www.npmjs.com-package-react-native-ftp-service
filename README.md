# react-native-ftp-service

Thư viện FTP service cho React Native

## Yêu cầu hệ thống

- Node.js >= 16
- React Native >= 0.70.0
- iOS: Xcode >= 14.0
- Android: Android Studio với Android SDK

## Cài đặt

### 1. Cài đặt thư viện

```sh
# Sử dụng npm
npm install react-native-ftp-service

# Hoặc sử dụng yarn
yarn add react-native-ftp-service
```

### 2. Cấu hình iOS

```sh
cd ios && pod install
```

### 3. Cấu hình Android

Đảm bảo rằng module FtpService được đăng ký trong `MainApplication.java`:

```java
package com.yourapp;

import com.facebook.react.ReactApplication;
import com.facebook.react.ReactNativeHost;
import com.facebook.react.ReactPackage;
import com.facebook.react.defaults.DefaultReactNativeHost;
import com.facebook.soloader.SoLoader;
import java.util.List;

// Thêm import này
import com.ftpservice.FtpServicePackage;

public class MainApplication extends Application implements ReactApplication {
  private final ReactNativeHost mReactNativeHost =
      new DefaultReactNativeHost(this) {
        @Override
        protected List<ReactPackage> getPackages() {
          @SuppressWarnings("UnnecessaryLocalVariable")
          List<ReactPackage> packages = new PackageList(this).getPackages();

          // Thêm dòng này để đăng ký FtpServicePackage
          packages.add(new FtpServicePackage());

          return packages;
        }

        // Còn lại của MainApplication.java
      };
}
```

**Lưu ý:** Nếu bạn đang sử dụng React Native CLI, có thể `react-native link` sẽ tự động thêm package này. Kiểm tra `MainApplication.java` để chắc chắn.

## Sử dụng

### 1. Kết nối FTP

```js
import FtpService from 'react-native-ftp-service';

// Kết nối đến máy chủ FTP
const connect = async () => {
  try {
    await FtpService.setup(host, port, username, password);
    console.log('Kết nối thành công');
  } catch (error) {
    console.error('Lỗi kết nối:', error);
  }
};
```

### 2. Liệt kê files và thư mục

```js
// Liệt kê files trong thư mục
const listFiles = async (path = '/') => {
  try {
    const files = await FtpService.listFiles(path);
    console.log('Danh sách files:', files);
  } catch (error) {
    console.error('Lỗi liệt kê files:', error);
  }
};
```

### 3. Tải file lên

```js
// Tải file lên server
const uploadFile = async (localPath, remotePath) => {
  try {
    const result = await FtpService.uploadFile(localPath, remotePath);
    console.log('Tải lên thành công:', result);
  } catch (error) {
    console.error('Lỗi tải lên:', error);
  }
};
```

### 4. Tải file xuống

```js
// Tải file từ server
const downloadFile = async (remotePath, localPath) => {
  try {
    const result = await FtpService.downloadFile(remotePath, localPath);
    console.log('Tải xuống thành công:', result);
  } catch (error) {
    console.error('Lỗi tải xuống:', error);
  }
};
```

### 5. Tạo thư mục mới

```js
// Tạo thư mục mới
const createDirectory = async (path) => {
  try {
    await FtpService.makeDirectory(path);
    console.log('Tạo thư mục thành công');
  } catch (error) {
    console.error('Lỗi tạo thư mục:', error);
  }
};
```

### 6. Xóa file hoặc thư mục

```js
// Xóa file
const deleteFile = async (path) => {
  try {
    await FtpService.deleteFile(path);
    console.log('Xóa file thành công');
  } catch (error) {
    console.error('Lỗi xóa file:', error);
  }
};

// Xóa thư mục
const deleteDirectory = async (path) => {
  try {
    await FtpService.deleteDirectory(path);
    console.log('Xóa thư mục thành công');
  } catch (error) {
    console.error('Lỗi xóa thư mục:', error);
  }
};
```

### 7. Đổi tên file hoặc thư mục

```js
// Đổi tên file hoặc thư mục
const rename = async (oldPath, newPath) => {
  try {
    await FtpService.rename(oldPath, newPath);
    console.log('Đổi tên thành công');
  } catch (error) {
    console.error('Lỗi đổi tên:', error);
  }
};
```

### 8. Theo dõi tiến trình

```js
// Thêm listener theo dõi tiến trình
const removeListener = FtpService.addProgressListener((info) => {
  console.log('Tiến trình:', info.percentage);
});

// Xóa listener khi không cần thiết
removeListener();
```

### 9. Tạm dừng và tiếp tục tác vụ

```js
// Tạo token để theo dõi tác vụ
const token = FtpService.makeProgressToken(localPath, remotePath);

// Tạm dừng tác vụ
const pauseTask = async () => {
  try {
    await FtpService.cancelUploadFile(token);
    console.log('Đã tạm dừng tác vụ');
  } catch (error) {
    console.error('Lỗi tạm dừng:', error);
  }
};
```

## Ví dụ đầy đủ

Bạn có thể xem ví dụ đầy đủ trong thư mục `example/` của dự án.

## Đóng góp

Xem hướng dẫn đóng góp tại [CONTRIBUTING.md](CONTRIBUTING.md) để tìm hiểu cách đóng góp vào repository và quy trình phát triển.

## Giấy phép

MIT

---

Được tạo bởi [create-react-native-library](https://github.com/callstack/react-native-builder-bob)
