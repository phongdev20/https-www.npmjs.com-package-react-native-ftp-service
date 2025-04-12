import * as React from 'react';
import {
  StyleSheet,
  View,
  Text,
  ScrollView,
  TextInput,
  PermissionsAndroid,
  Platform,
  Alert,
  TouchableOpacity,
  ActivityIndicator,
  SafeAreaView,
  StatusBar,
  Modal,
  Linking,
} from 'react-native';
import FtpService, {
  type ProgressInfo,
  type FileInfo,
  type TaskToken,
} from 'react-native-ftp-service';
import RNFS from 'react-native-fs';

function PlatformInfo() {
  return (
    <View style={styles.infoBox}>
      <Text style={styles.infoTitle}>Thông tin hệ thống</Text>
      <Text style={styles.infoText}>Platform: {Platform.OS}</Text>
      <Text style={styles.infoText}>Version: {Platform.Version}</Text>
      <Text style={styles.infoText}>
        Default dir:{' '}
        {Platform.OS === 'ios'
          ? RNFS.DocumentDirectoryPath
          : RNFS.DownloadDirectoryPath}
      </Text>
    </View>
  );
}

function ProgressBar({ progress }: { progress: number }) {
  return (
    <View style={styles.progressContainer}>
      <View style={styles.progressBackground}>
        <View style={[styles.progressFill, { width: `${progress}%` }]} />
      </View>
      <Text style={styles.progressText}>{Math.round(progress)}%</Text>
    </View>
  );
}

function FileListItem({
  item,
  currentPath,
  onNavigate,
  onDownload,
  onDelete,
  onRename,
}: {
  item: FileInfo;
  currentPath: string;
  onNavigate: (path: string) => void;
  onDownload: (path: string) => void;
  onDelete: (path: string, isDir: boolean) => void;
  onRename: (item: { path: string; name: string; isDir: boolean }) => void;
}) {
  // Xác định xem item có phải là thư mục không (hỗ trợ cả 'directory' và 'dir')
  const isDirectory = item.type === 'directory' || item.type === 'dir';
  const fullPath =
    currentPath === '/' ? '/' + item.name : currentPath + '/' + item.name;

  return (
    <View style={styles.fileItem}>
      <TouchableOpacity
        style={styles.fileButton}
        onPress={() =>
          isDirectory ? onNavigate(fullPath) : onDownload(fullPath)
        }
      >
        <Text
          style={[
            styles.fileIcon,
            isDirectory ? styles.folderIcon : styles.docIcon,
          ]}
        >
          {isDirectory ? '📁' : '📄'}
        </Text>
        <View style={styles.fileDetails}>
          <Text style={styles.fileName}>{item.name}</Text>
          <Text style={styles.fileInfo}>
            {isDirectory ? 'Thư mục' : `${(item.size / 1024).toFixed(1)} KB`}
          </Text>
        </View>
      </TouchableOpacity>

      <View style={styles.fileActions}>
        {isDirectory && (
          <TouchableOpacity
            style={styles.openButton}
            onPress={() => onNavigate(fullPath)}
          >
            <Text style={styles.openButtonText}>Mở</Text>
          </TouchableOpacity>
        )}
        <TouchableOpacity
          style={styles.actionIconButton}
          onPress={() => {
            onRename({ path: fullPath, name: item.name, isDir: isDirectory });
          }}
        >
          <Text style={styles.actionIconText}>Đổi tên</Text>
        </TouchableOpacity>

        <TouchableOpacity
          style={styles.deleteButton}
          onPress={() => {
            Alert.alert(
              `Xóa ${isDirectory ? 'thư mục' : 'tệp tin'}`,
              `Bạn có chắc muốn xóa ${item.name}?`,
              [
                { text: 'Hủy', style: 'cancel' },
                {
                  text: 'Xóa',
                  onPress: () => onDelete(fullPath, isDirectory),
                  style: 'destructive',
                },
              ]
            );
          }}
        >
          <Text style={styles.deleteButtonText}>Xóa</Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

export default function App() {
  const [status, setStatus] = React.useState('');
  const [files, setFiles] = React.useState<FileInfo[]>([]);
  const [host, setHost] = React.useState('eu-central-1.sftpcloud.io');
  const [port, setPort] = React.useState('21');
  const [username, setUsername] = React.useState(
    'b7147c3f91274e84a23cf401d2f3dc9f'
  );
  const [password, setPassword] = React.useState(
    's48Tgh6HkCi1sP4sDFj0TyzwqrwTvQyh'
  );
  const [remotePath, setRemotePath] = React.useState('/');
  const [isUploading, setIsUploading] = React.useState(false);
  const [isDownloading, setIsDownloading] = React.useState(false);
  const [isConnecting, setIsConnecting] = React.useState(false);
  const [isConnected, setIsConnected] = React.useState(false);
  const [progress, setProgress] = React.useState(0);
  const [newDirName, setNewDirName] = React.useState('');
  const [showNewDirModal, setShowNewDirModal] = React.useState(false);
  const [renameItem, setRenameItem] = React.useState<{
    path: string;
    name: string;
    isDir: boolean;
  } | null>(null);
  const [newFileName, setNewFileName] = React.useState('');
  const [pathHistory, setPathHistory] = React.useState<string[]>(['/']);
  const [currentHistoryIndex, setCurrentHistoryIndex] = React.useState(0);
  const [recentDirectories, setRecentDirectories] = React.useState<string[]>(
    []
  );
  const [showBrowseHistory, setShowBrowseHistory] = React.useState(false);

  // Thêm biến state cho chức năng tạm dừng
  const [isPaused, setIsPaused] = React.useState(false);
  const [currentUploadToken, setCurrentUploadToken] =
    React.useState<TaskToken | null>(null);
  const [currentDownloadToken, setCurrentDownloadToken] =
    React.useState<TaskToken | null>(null);
  const [pausedTransferData, setPausedTransferData] = React.useState<{
    type: 'upload' | 'download';
    localPath: string;
    remotePath: string;
  } | null>(null);

  // Theo dõi tiến trình tải lên/xuống
  React.useEffect(() => {
    const removeListener = FtpService.addProgressListener(
      (info: ProgressInfo) => {
        setProgress(info.percentage);
      }
    );

    // Xóa listener khi component unmount
    return () => {
      removeListener();
    };
  }, []);

  // Kiểm tra trạng thái kết nối
  const checkConnection = React.useCallback(async () => {
    try {
      // Thử liệt kê files để kiểm tra kết nối
      await FtpService.listFiles(remotePath);
      return true;
    } catch (error: any) {
      // Nếu có lỗi, giả định kết nối đã đóng
      if (isConnected) {
        setIsConnected(false);
        setStatus('Kết nối đã bị đóng: ' + error.message);

        // Hiển thị cảnh báo cho người dùng
        Alert.alert(
          'Kết nối bị ngắt',
          'Kết nối FTP đã bị đóng mà không có thông báo từ server. Vui lòng kết nối lại.',
          [{ text: 'OK' }]
        );
      }
      return false;
    }
  }, [remotePath, isConnected]);

  // Hàm xử lý lỗi kết nối
  const handleConnectionError = React.useCallback(
    (error: any) => {
      const errorMsg = error.message || '';

      if (
        errorMsg.includes('connection') ||
        errorMsg.includes('timeout') ||
        errorMsg.includes('closed') ||
        errorMsg.includes('EOF')
      ) {
        if (isConnected) {
          setIsConnected(false);
          setStatus('Kết nối đã bị đóng: ' + errorMsg);

          // Hiển thị cảnh báo cho người dùng
          Alert.alert(
            'Kết nối bị ngắt',
            'Kết nối FTP đã bị đóng mà không có thông báo từ server. Vui lòng kết nối lại.',
            [{ text: 'OK' }]
          );
        }
        return true;
      }
      return false;
    },
    [isConnected]
  );

  // Kết nối đến máy chủ FTP
  const connect = async () => {
    try {
      setIsConnecting(true);
      setStatus('Đang kết nối...');

      // Sử dụng phương thức setup mới
      await FtpService.setup(host, parseInt(port, 10), username, password);
      setStatus('Kết nối & đăng nhập thành công');
      setIsConnected(true);

      // Liệt kê files trong thư mục root
      await listFiles();
    } catch (error: any) {
      console.log(error.message);
      setStatus('Lỗi kết nối: ' + error.message);
      setIsConnected(false);
    } finally {
      setIsConnecting(false);
    }
  };

  // Ngắt kết nối
  const disconnect = async () => {
    try {
      // Không có phương thức disconnect() trong API mới, chỉ cần cập nhật UI
      setIsConnected(false);
      setFiles([]);
      setStatus('Đã ngắt kết nối');
    } catch (error: any) {
      setStatus('Lỗi ngắt kết nối: ' + error.message);
    }
  };

  // Liệt kê files trong thư mục
  const listFiles = React.useCallback(async () => {
    try {
      setStatus('Đang tải danh sách...');
      const result = await FtpService.listFiles(remotePath);
      setFiles(result);
      setStatus('Đã lấy danh sách file từ: ' + remotePath);
    } catch (error: any) {
      console.log(error.message);
      setStatus('Lỗi lấy danh sách: ' + error.message);
      // Xử lý lỗi kết nối bằng hàm chung
      handleConnectionError(error);
    }
  }, [remotePath, handleConnectionError]);

  // Điều hướng đến thư mục
  const navigateToDirectory = async (path: string) => {
    // Kiểm tra kết nối trước khi thực hiện thao tác
    if (!(await checkConnection())) {
      return;
    }

    // Thêm thư mục vào danh sách gần đây nếu chưa có
    setRecentDirectories((prev) => {
      if (!prev.includes(path) && path !== '/') {
        // Giữ tối đa 5 thư mục gần đây
        const newList = [path, ...prev.filter((p) => p !== path)].slice(0, 5);
        return newList;
      }
      return prev;
    });

    setRemotePath(path);

    // Cập nhật lịch sử điều hướng
    if (currentHistoryIndex < pathHistory.length - 1) {
      // Nếu đang ở giữa lịch sử, cắt bỏ phần phía sau
      setPathHistory((prev) => [
        ...prev.slice(0, currentHistoryIndex + 1),
        path,
      ]);
    } else {
      // Nếu đang ở cuối lịch sử, thêm vào
      setPathHistory((prev) => [...prev, path]);
    }
    setCurrentHistoryIndex((prev) => prev + 1);
  };

  // Quay lại thư mục trước đó
  const navigateBack = () => {
    if (currentHistoryIndex > 0) {
      const newIndex = currentHistoryIndex - 1;
      setCurrentHistoryIndex(newIndex);
      const previousPath = pathHistory[newIndex];
      if (previousPath) {
        setRemotePath(previousPath);
      }
    }
  };

  // Tiến tới thư mục phía trước
  const navigateForward = () => {
    if (currentHistoryIndex < pathHistory.length - 1) {
      const newIndex = currentHistoryIndex + 1;
      setCurrentHistoryIndex(newIndex);
      const nextPath = pathHistory[newIndex];
      if (nextPath) {
        setRemotePath(nextPath);
      }
    }
  };

  // Tạo thư mục mới
  const createDirectory = async () => {
    try {
      if (!newDirName.trim()) {
        Alert.alert('Lỗi', 'Vui lòng nhập tên thư mục');
        return;
      }

      const fullPath =
        remotePath === '/' ? `/${newDirName}` : `${remotePath}/${newDirName}`;

      setStatus('Đang tạo thư mục...');
      // Sử dụng phương thức mới để tạo thư mục
      await FtpService.makeDirectory(fullPath);

      setStatus(`Đã tạo thư mục: ${newDirName}`);
      setShowNewDirModal(false);
      setNewDirName('');

      // Cập nhật danh sách để hiển thị thư mục mới
      await listFiles();
    } catch (error: any) {
      if (!handleConnectionError(error)) {
        setStatus(`Lỗi tạo thư mục: ${error.message}`);
      }
    }
  };

  // Xóa file hoặc thư mục
  const deleteItem = async (path: string, isDirectory: boolean) => {
    // Kiểm tra kết nối trước khi thực hiện thao tác
    if (!(await checkConnection())) {
      return;
    }

    try {
      setStatus(`Đang xóa ${isDirectory ? 'thư mục' : 'tệp tin'}...`);

      let result;
      if (isDirectory) {
        // Xóa thư mục
        result = await FtpService.deleteDirectory(path);
      } else {
        // Xóa file
        result = await FtpService.deleteFile(path);
      }

      setStatus(result ? 'Xóa thành công' : 'Xóa thất bại');
      await listFiles(); // Cập nhật danh sách
    } catch (error: any) {
      setStatus(
        `Lỗi xóa ${isDirectory ? 'thư mục' : 'tệp tin'}: ` + error.message
      );
      // Xử lý lỗi kết nối bằng hàm chung
      handleConnectionError(error);
    }
  };

  // Đổi tên file hoặc thư mục
  const renameFileOrDir = async () => {
    try {
      if (!renameItem || !newFileName.trim()) {
        Alert.alert('Lỗi', 'Vui lòng nhập tên mới');
        return;
      }

      const dirPath = remotePath === '/' ? '' : remotePath;
      const oldPath = `${dirPath}/${renameItem.name}`;
      const newPath = `${dirPath}/${newFileName}`;

      setStatus('Đang đổi tên...');
      // Sử dụng phương thức mới để đổi tên
      await FtpService.rename(oldPath, newPath);

      setStatus('Đã đổi tên thành công');
      setRenameItem(null);
      setNewFileName('');

      // Cập nhật danh sách
      await listFiles();
    } catch (error: any) {
      if (!handleConnectionError(error)) {
        setStatus(`Lỗi đổi tên: ${error.message}`);
      }
    }
  };

  // Xin quyền truy cập bộ nhớ
  const requestStoragePermission = async (): Promise<boolean> => {
    if (Platform.OS !== 'android') {
      return true; // iOS không cần xin quyền riêng
    }

    try {
      const androidVersion = parseInt(Platform.Version.toString(), 10);

      if (androidVersion >= 33) {
        // Android 13 (API 33) trở lên
        return true;
      } else if (androidVersion >= 29) {
        // Android 10 (API 29) trở lên
        try {
          const granted = await PermissionsAndroid.request(
            PermissionsAndroid.PERMISSIONS.READ_EXTERNAL_STORAGE,
            {
              title: 'Quyền truy cập bộ nhớ',
              message: 'Ứng dụng cần quyền để lưu file tải về',
              buttonNeutral: 'Hỏi lại sau',
              buttonNegative: 'Từ chối',
              buttonPositive: 'Đồng ý',
            }
          );
          return granted === PermissionsAndroid.RESULTS.GRANTED;
        } catch (err) {
          console.warn(err);
          return false;
        }
      } else {
        // Android 9 và cũ hơn
        const readGranted = await PermissionsAndroid.request(
          PermissionsAndroid.PERMISSIONS.READ_EXTERNAL_STORAGE
        );
        const writeGranted = await PermissionsAndroid.request(
          PermissionsAndroid.PERMISSIONS.WRITE_EXTERNAL_STORAGE
        );
        return (
          readGranted === PermissionsAndroid.RESULTS.GRANTED &&
          writeGranted === PermissionsAndroid.RESULTS.GRANTED
        );
      }
    } catch (err) {
      console.warn(err);
      return false;
    }
  };

  // Tạm dừng tác vụ hiện tại
  const pauseCurrentTask = async () => {
    try {
      // Kiểm tra xem có tác vụ nào đang chạy không
      if (isUploading && currentUploadToken) {
        // Lưu thông tin tác vụ upload để có thể khôi phục
        const localPathStr = currentUploadToken.split('=>')[0];
        const remotePathStr = currentUploadToken.split('=>')[1];

        if (localPathStr && remotePathStr) {
          setPausedTransferData({
            type: 'upload',
            localPath: localPathStr,
            remotePath: remotePathStr,
          });

          // Hủy tác vụ upload hiện tại
          await FtpService.cancelUploadFile(currentUploadToken);
          setCurrentUploadToken(null);
          setIsUploading(false);
          setIsPaused(true);
          setStatus('Đã tạm dừng tải lên');
        }
      } else if (isDownloading && currentDownloadToken) {
        // Lưu thông tin tác vụ download để có thể khôi phục
        const localPathStr = currentDownloadToken.split('<=')[0];
        const remotePathStr = currentDownloadToken.split('<=')[1];

        if (localPathStr && remotePathStr) {
          setPausedTransferData({
            type: 'download',
            localPath: localPathStr,
            remotePath: remotePathStr,
          });

          // Hủy tác vụ download hiện tại
          await FtpService.cancelDownloadFile(currentDownloadToken);
          setCurrentDownloadToken(null);
          setIsDownloading(false);
          setIsPaused(true);
          setStatus('Đã tạm dừng tải xuống');
        }
      } else {
        setStatus('Không có tác vụ nào đang chạy để tạm dừng');
      }
    } catch (error: any) {
      setStatus('Lỗi khi tạm dừng: ' + error.message);
    }
  };

  // Tiếp tục tác vụ đã tạm dừng
  const resumeTask = async () => {
    try {
      if (!isPaused || !pausedTransferData) {
        setStatus('Không có tác vụ nào đang tạm dừng');
        return;
      }

      // Extract paths to local variables to avoid shadowing
      const {
        localPath: localPathToUse,
        remotePath: remotePathToUse,
        type,
      } = pausedTransferData;

      // Khôi phục tác vụ dựa trên loại
      if (type === 'upload') {
        // Khởi động lại việc tải lên từ đầu
        const token = FtpService.makeProgressToken(
          localPathToUse,
          remotePathToUse
        );
        setCurrentUploadToken(token);
        setProgress(0);
        setIsUploading(true);
        setIsPaused(false);
        setStatus('Đang tiếp tục tải lên...');

        const result = await FtpService.uploadFile(
          localPathToUse,
          remotePathToUse
        );

        setStatus(`Tải lên hoàn tất: ${result}`);
        await listFiles(); // Cập nhật danh sách
        setIsUploading(false);
        setPausedTransferData(null);
      } else if (type === 'download') {
        // Khởi động lại việc tải xuống từ đầu
        const token = FtpService.makeProgressToken(
          localPathToUse,
          remotePathToUse,
          true
        );
        setCurrentDownloadToken(token);
        setProgress(0);
        setIsDownloading(true);
        setIsPaused(false);
        setStatus('Đang tiếp tục tải xuống...');

        const result = await FtpService.downloadFile(
          localPathToUse,
          remotePathToUse
        );

        // Thông báo thành công
        Alert.alert(
          'Tải xuống hoàn tất',
          `File đã được lưu tại: ${localPathToUse}`,
          [{ text: 'OK' }]
        );

        setStatus(result ? 'Tải xuống thành công' : 'Tải xuống thất bại');
        setIsDownloading(false);
        setPausedTransferData(null);
      }
    } catch (error: any) {
      setStatus('Lỗi khi tiếp tục: ' + error.message);
      // Xử lý lỗi kết nối
      handleConnectionError(error);
      setIsPaused(false);
      setIsUploading(false);
      setIsDownloading(false);
      setPausedTransferData(null);
    }
  };

  // Hủy tác vụ đã tạm dừng
  const cancelPausedTask = () => {
    setIsPaused(false);
    setPausedTransferData(null);
    setStatus('Đã hủy tác vụ tạm dừng');
  };

  // Tải file xuống
  const downloadFile = async (remoteFilePath: string) => {
    // Kiểm tra kết nối trước khi thực hiện thao tác
    if (!(await checkConnection())) {
      return;
    }

    try {
      // Xin quyền truy cập bộ nhớ
      const hasPermission = await requestStoragePermission();

      if (!hasPermission) {
        Alert.alert(
          'Quyền bị từ chối',
          'Bạn cần cấp quyền truy cập bộ nhớ để tải file',
          [{ text: 'OK' }]
        );
        setStatus('Không thể tải xuống: Quyền lưu trữ bị từ chối');
        return;
      }

      const fileName = remoteFilePath.split('/').pop();

      // Kiểm tra tên file hợp lệ
      if (!fileName) {
        setStatus('Lỗi: Không thể xác định tên file');
        return;
      }

      if (Platform.OS === 'ios') {
        const downloadPath = `${RNFS.DocumentDirectoryPath}/${fileName}`;
        await handleDownload(downloadPath, remoteFilePath, fileName);
      } else {
        // Android: hiển thị dialog cho người dùng chọn
        Alert.alert('Chọn vị trí lưu file', 'Bạn muốn lưu file ở đâu?', [
          {
            text: 'Thư mục Download',
            onPress: () => {
              try {
                const downloadPath = `${RNFS.DownloadDirectoryPath}/${fileName}`;
                handleDownload(downloadPath, remoteFilePath, fileName);
              } catch (err: any) {
                setStatus('Lỗi tải xuống: ' + err.message);
              }
            },
          },
          {
            text: 'Thư mục ứng dụng',
            onPress: () => {
              try {
                const downloadPath = `${RNFS.ExternalDirectoryPath}/${fileName}`;
                handleDownload(downloadPath, remoteFilePath, fileName);
              } catch (err: any) {
                setStatus('Lỗi tải xuống: ' + err.message);
              }
            },
          },
          {
            text: 'Hủy',
            style: 'cancel',
            onPress: () => {
              setStatus('Đã hủy tải xuống');
            },
          },
        ]);
      }
    } catch (error: any) {
      setStatus('Lỗi tải xuống: ' + error.message);
      handleConnectionError(error);
    }
  };

  // Hàm xử lý tổng thể việc tải xuống
  const handleDownload = async (
    downloadPath: string,
    remoteFilePath: string,
    fileName: string
  ) => {
    try {
      // Kiểm tra xem file đã tồn tại chưa
      const fileExists = await RNFS.exists(downloadPath);

      if (fileExists) {
        Alert.alert(
          'File đã tồn tại',
          'File này đã tồn tại. Bạn muốn thay thế hay tải với tên khác?',
          [
            {
              text: 'Thay thế',
              onPress: async () => {
                try {
                  // Xóa file cũ trước khi tải xuống file mới
                  setStatus('Đang xóa file cũ...');
                  await RNFS.unlink(downloadPath).catch((err: any) => {
                    console.log('Lỗi khi xóa file cũ: ', err);
                    // Tiếp tục ngay cả khi không xóa được, vì FTP có thể ghi đè
                  });

                  // Sau khi xóa, tiến hành tải xuống file mới
                  executeDownload(downloadPath, remoteFilePath).catch((err) => {
                    setStatus('Lỗi tải xuống: ' + err.message);
                  });
                } catch (err: any) {
                  console.error('Lỗi trong quá trình thay thế file: ', err);
                  setStatus('Lỗi khi thay thế file: ' + err.message);
                }
              },
            },
            {
              text: 'Tải với tên khác',
              onPress: () => {
                try {
                  const timestamp = new Date().getTime();
                  const newPath = downloadPath.replace(
                    fileName,
                    `${timestamp}_${fileName}`
                  );
                  executeDownload(newPath, remoteFilePath).catch((err) => {
                    setStatus('Lỗi tải xuống: ' + err.message);
                  });
                } catch (err: any) {
                  setStatus('Lỗi khi tạo tên file mới: ' + err.message);
                }
              },
            },
            {
              text: 'Hủy',
              style: 'cancel',
              onPress: () => {
                setStatus('Đã hủy tải xuống');
              },
            },
          ]
        );
      } else {
        await executeDownload(downloadPath, remoteFilePath);
      }
    } catch (error: any) {
      setStatus('Lỗi khi kiểm tra file: ' + error.message);
    }
  };

  // Thực hiện tải xuống
  const executeDownload = async (
    downloadPath: string,
    remoteFilePath: string
  ) => {
    try {
      // Đảm bảo thư mục cha tồn tại
      const dirPath = downloadPath.substring(0, downloadPath.lastIndexOf('/'));
      const dirExists = await RNFS.exists(dirPath);

      if (!dirExists && Platform.OS === 'android') {
        await RNFS.mkdir(dirPath);
      }

      setProgress(0);
      setIsDownloading(true);
      setStatus('Đang tải xuống...');

      // Lưu token để có thể tạm dừng
      const token = FtpService.makeProgressToken(
        downloadPath,
        remoteFilePath,
        true
      );
      setCurrentDownloadToken(token);

      // Thực hiện tải xuống
      const result = await FtpService.downloadFile(
        downloadPath,
        remoteFilePath
      );

      if (!result) {
        setStatus('Tải xuống thất bại');
        setCurrentDownloadToken(null);
        setIsDownloading(false);
        return false;
      }

      // Kiểm tra file tồn tại sau khi tải
      const fileExists = await RNFS.exists(downloadPath);
      if (!fileExists) {
        setStatus('Tải xuống thất bại: File không tồn tại sau khi tải');
        setCurrentDownloadToken(null);
        setIsDownloading(false);
        return false;
      }

      // Kiểm tra xem file có thể mở được không
      let canOpen = false;
      try {
        canOpen = await checkIfFileCanBeOpened(downloadPath);
      } catch (err) {
        console.log('Không thể kiểm tra khả năng mở file', err);
      }

      // Thông báo thành công
      const buttons = [{ text: 'OK' }] as Array<{
        text: string;
        onPress?: () => void;
        style?: 'default' | 'cancel' | 'destructive';
      }>;

      if (canOpen) {
        buttons.push({
          text: 'Mở file',
          onPress: () => {
            try {
              openDownloadedFile(downloadPath);
            } catch (err: any) {
              setStatus('Không thể mở file: ' + err.message);
            }
          },
        });
      }

      Alert.alert(
        'Tải xuống hoàn tất',
        `File đã được lưu tại: ${downloadPath}`,
        buttons
      );

      setStatus('Tải xuống thành công');
      setCurrentDownloadToken(null);
      return true;
    } catch (error: any) {
      setStatus('Lỗi tải xuống: ' + error.message);
      handleConnectionError(error);
      setCurrentDownloadToken(null);
      return false;
    } finally {
      setIsDownloading(false);
    }
  };

  // Kiểm tra xem file có thể mở được không
  const checkIfFileCanBeOpened = async (filePath: string) => {
    try {
      const extension = filePath.split('.').pop()?.toLowerCase();
      // Kiểm tra theo định dạng file phổ biến
      const openableExtensions = [
        'pdf',
        'jpg',
        'jpeg',
        'png',
        'txt',
        'doc',
        'docx',
        'xls',
        'xlsx',
        'ppt',
        'pptx',
      ];
      return openableExtensions.includes(extension || '');
    } catch (error) {
      return false;
    }
  };

  // Mở file đã tải xuống
  const openDownloadedFile = async (filePath: string) => {
    try {
      // Sử dụng Linking để mở file
      if (Platform.OS === 'android') {
        const fileUri = `file://${filePath}`;
        const canOpen = await Linking.canOpenURL(fileUri);

        if (canOpen) {
          await Linking.openURL(fileUri);
        } else {
          setStatus('Không thể mở file: Không có ứng dụng hỗ trợ');
        }
      } else if (Platform.OS === 'ios') {
        RNFS.readFile(filePath, 'base64')
          .then(() => {
            // Trên iOS, bạn có thể sử dụng QuickLook hoặc các thư viện khác để mở file
            setStatus('iOS chưa hỗ trợ mở file trực tiếp trong ứng dụng này');
          })
          .catch((error) => {
            setStatus('Không thể đọc file: ' + error.message);
          });
      }
    } catch (error: any) {
      setStatus('Không thể mở file: ' + error.message);
    }
  };

  // Tải file lên
  const uploadFile = async () => {
    // Kiểm tra kết nối trước khi thực hiện thao tác
    if (!(await checkConnection())) {
      return;
    }

    try {
      // Tạo file test để tải lên
      const fileName = 'test_upload.txt';
      // Sử dụng DocumentDirectoryPath cho iOS để tránh vấn đề quyền truy cập
      const localPath =
        Platform.OS === 'ios'
          ? `${RNFS.DocumentDirectoryPath}/${fileName}`
          : `${RNFS.CachesDirectoryPath}/${fileName}`;

      // Đảm bảo thư mục tồn tại
      const dirPath = localPath.substring(0, localPath.lastIndexOf('/'));
      const dirExists = await RNFS.exists(dirPath);
      if (!dirExists) {
        await RNFS.mkdir(dirPath);
      }

      // Định nghĩa đường dẫn upload
      const uploadPath =
        remotePath === '/' ? `/${fileName}` : `${remotePath}/${fileName}`;

      // Tạo nội dung file test
      try {
        await RNFS.writeFile(
          localPath,
          'Đây là file test để tải lên FTP server',
          'utf8'
        );
      } catch (writeError: any) {
        console.error('Lỗi khi tạo file test:', writeError);
        setStatus('Lỗi khi tạo file test: ' + writeError.message);
        return;
      }

      // Kiểm tra file đã được tạo thành công
      const fileExists = await RNFS.exists(localPath);
      if (!fileExists) {
        setStatus('Lỗi: Không thể tạo file test');
        return;
      }

      // Lưu token để có thể tạm dừng
      const token = FtpService.makeProgressToken(localPath, uploadPath);
      setCurrentUploadToken(token);

      setProgress(0);
      setIsUploading(true);
      setStatus('Đang tải lên...');

      const result = await FtpService.uploadFile(localPath, uploadPath);
      setStatus(`Tải lên hoàn tất: ${result}`);
      await listFiles(); // Cập nhật danh sách
      setCurrentUploadToken(null);
    } catch (error: any) {
      const errorMsg = error.message || 'Lỗi không xác định';
      console.error('Upload error:', errorMsg);
      setStatus('Lỗi tải lên: ' + errorMsg);
      // Xử lý lỗi kết nối bằng hàm chung
      handleConnectionError(error);
      setCurrentUploadToken(null);
    } finally {
      setIsUploading(false);
    }
  };

  // Hiển thị trạng thái kết nối
  const renderConnectionStatus = () => {
    if (isConnecting) {
      return (
        <View style={styles.statusIndicator}>
          <ActivityIndicator size="small" color="#0066cc" />
          <Text style={styles.statusText}>Đang kết nối...</Text>
        </View>
      );
    }

    if (isConnected) {
      return (
        <View style={styles.statusIndicator}>
          <View style={[styles.statusDot, styles.connectedDot]} />
          <Text style={styles.statusText}>Đã kết nối</Text>
        </View>
      );
    }

    return (
      <View style={styles.statusIndicator}>
        <View style={[styles.statusDot, styles.disconnectedDot]} />
        <Text style={styles.statusText}>Chưa kết nối</Text>
      </View>
    );
  };

  // Cập nhật danh sách files khi đổi thư mục
  React.useEffect(() => {
    if (isConnected) {
      listFiles();
    }
  }, [remotePath, isConnected, listFiles]);

  // Thêm kiểm tra kết nối định kỳ
  React.useEffect(() => {
    let connectionCheck: NodeJS.Timeout;

    if (isConnected) {
      // Kiểm tra kết nối mỗi 30 giây
      connectionCheck = setInterval(async () => {
        await checkConnection();
      }, 30000);
    }

    return () => {
      if (connectionCheck) {
        clearInterval(connectionCheck);
      }
    };
  }, [isConnected, checkConnection, remotePath]);

  return (
    <SafeAreaView style={styles.container}>
      <StatusBar barStyle="dark-content" backgroundColor="#f0f0f0" />

      <View style={styles.header}>
        <Text style={styles.headerTitle}>FTP Handler</Text>
        {renderConnectionStatus()}
      </View>

      <ScrollView style={styles.scrollView}>
        {/* Thông tin hệ thống */}
        <PlatformInfo />

        {/* Form kết nối FTP */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Kết nối FTP</Text>

          <TextInput
            style={styles.input}
            placeholder="Host"
            value={host}
            onChangeText={setHost}
            editable={!isConnected}
          />

          <TextInput
            style={styles.input}
            placeholder="Port"
            value={port}
            onChangeText={setPort}
            keyboardType="numeric"
            editable={!isConnected}
          />

          <TextInput
            style={styles.input}
            placeholder="Username"
            value={username}
            onChangeText={setUsername}
            editable={!isConnected}
          />

          <TextInput
            style={styles.input}
            placeholder="Password"
            value={password}
            onChangeText={setPassword}
            secureTextEntry={true}
            editable={!isConnected}
          />

          <View style={styles.buttonContainer}>
            {!isConnected ? (
              <TouchableOpacity
                style={styles.primaryButton}
                onPress={connect}
                disabled={isConnecting}
              >
                <Text style={styles.buttonText}>
                  {isConnecting ? 'Đang kết nối...' : 'Kết nối'}
                </Text>
              </TouchableOpacity>
            ) : (
              <TouchableOpacity
                style={styles.secondaryButton}
                onPress={disconnect}
              >
                <Text style={styles.buttonText}>Ngắt kết nối</Text>
              </TouchableOpacity>
            )}
          </View>
        </View>

        {/* Hiển thị đường dẫn hiện tại */}
        {isConnected && (
          <View style={styles.pathContainer}>
            <View style={styles.navButtons}>
              <TouchableOpacity
                style={[
                  styles.navButton,
                  currentHistoryIndex === 0 && styles.disabledButton,
                ]}
                onPress={navigateBack}
                disabled={currentHistoryIndex === 0}
              >
                <Text
                  style={[
                    styles.navButtonText,
                    currentHistoryIndex === 0 && styles.disabledText,
                  ]}
                >
                  ←
                </Text>
              </TouchableOpacity>

              <TouchableOpacity
                style={[
                  styles.navButton,
                  currentHistoryIndex >= pathHistory.length - 1 &&
                    styles.disabledButton,
                ]}
                onPress={navigateForward}
                disabled={currentHistoryIndex >= pathHistory.length - 1}
              >
                <Text
                  style={[
                    styles.navButtonText,
                    currentHistoryIndex >= pathHistory.length - 1 &&
                      styles.disabledText,
                  ]}
                >
                  →
                </Text>
              </TouchableOpacity>
            </View>

            <View style={styles.breadcrumbContainer}>
              {remotePath.split('/').map((part, index, array) => {
                if (!part && index === 0) {
                  // Root directory
                  return (
                    <TouchableOpacity
                      key="root"
                      style={styles.breadcrumbItem}
                      onPress={() => navigateToDirectory('/')}
                    >
                      <Text style={styles.breadcrumbText}>Gốc</Text>
                    </TouchableOpacity>
                  );
                } else if (part) {
                  // Build the path up to this part
                  const pathUpToHere =
                    '/' + array.slice(1, index + 1).join('/');
                  return (
                    <React.Fragment key={index}>
                      <Text style={styles.breadcrumbSeparator}>/</Text>
                      <TouchableOpacity
                        style={styles.breadcrumbItem}
                        onPress={() => navigateToDirectory(pathUpToHere)}
                      >
                        <Text style={styles.breadcrumbText}>{part}</Text>
                      </TouchableOpacity>
                    </React.Fragment>
                  );
                }
                return null;
              })}
            </View>

            <TouchableOpacity
              style={styles.historyButton}
              onPress={() => setShowBrowseHistory(!showBrowseHistory)}
            >
              <Text style={styles.historyButtonText}>⋮</Text>
            </TouchableOpacity>
          </View>
        )}

        {/* Hiển thị menu thư mục gần đây */}
        {isConnected && showBrowseHistory && (
          <View style={styles.historyMenu}>
            <Text style={styles.historyMenuTitle}>Thư mục gần đây</Text>
            {recentDirectories.length > 0 ? (
              recentDirectories.map((path, index) => (
                <TouchableOpacity
                  key={index}
                  style={styles.historyMenuItem}
                  onPress={() => {
                    navigateToDirectory(path);
                    setShowBrowseHistory(false);
                  }}
                >
                  <Text style={styles.historyMenuItemIcon}>📁</Text>
                  <Text style={styles.historyMenuItemText}>{path}</Text>
                </TouchableOpacity>
              ))
            ) : (
              <Text style={styles.emptyHistoryText}>
                Chưa có thư mục nào được truy cập gần đây
              </Text>
            )}
          </View>
        )}

        {/* Danh sách files và thư mục */}
        {isConnected && (
          <View style={styles.section}>
            <View style={styles.sectionHeader}>
              <Text style={styles.sectionTitle}>Danh sách file</Text>

              <View style={styles.actionsContainer}>
                <TouchableOpacity
                  style={styles.actionButton}
                  onPress={() => setShowNewDirModal(true)}
                >
                  <Text style={styles.actionButtonText}>Tạo thư mục</Text>
                </TouchableOpacity>

                <TouchableOpacity
                  style={styles.actionButton}
                  onPress={uploadFile}
                  disabled={isUploading}
                >
                  <Text style={styles.actionButtonText}>
                    {isUploading ? 'Đang tải lên...' : 'Tải lên'}
                  </Text>
                </TouchableOpacity>

                <TouchableOpacity
                  style={styles.actionButton}
                  onPress={listFiles}
                >
                  <Text style={styles.actionButtonText}>Làm mới</Text>
                </TouchableOpacity>
              </View>
            </View>

            {files.length > 0 ? (
              <View style={styles.fileList}>
                {files.map((item, index) => (
                  <FileListItem
                    key={index}
                    item={item}
                    currentPath={remotePath}
                    onNavigate={navigateToDirectory}
                    onDownload={downloadFile}
                    onDelete={deleteItem}
                    onRename={(item) => {
                      setRenameItem(item);
                      setNewFileName(item.name);
                    }}
                  />
                ))}
              </View>
            ) : (
              <View style={styles.emptyDirectoryContainer}>
                <Text style={styles.emptyDirectoryIcon}>📂</Text>
                <Text style={styles.emptyDirectoryTitle}>Thư mục trống</Text>
                <Text style={styles.emptyMessage}>
                  Không có file hoặc thư mục nào trong "
                  {remotePath === '/'
                    ? 'Thư mục gốc'
                    : remotePath.split('/').pop()}
                  "
                </Text>
                <TouchableOpacity
                  style={styles.emptyDirCreateButton}
                  onPress={() => setShowNewDirModal(true)}
                >
                  <Text style={styles.emptyDirCreateButtonText}>
                    Tạo thư mục mới
                  </Text>
                </TouchableOpacity>
              </View>
            )}
          </View>
        )}

        {/* Hiển thị tiến trình */}
        {(isUploading || isDownloading) && (
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>
              {isUploading ? 'Tiến trình tải lên' : 'Tiến trình tải xuống'}
            </Text>
            <ProgressBar progress={progress} />

            <TouchableOpacity
              style={styles.pauseButton}
              onPress={pauseCurrentTask}
            >
              <Text style={styles.pauseButtonText}>Tạm dừng</Text>
            </TouchableOpacity>
          </View>
        )}

        {/* Hiển thị tác vụ tạm dừng */}
        {isPaused && pausedTransferData && (
          <View style={styles.section}>
            <Text style={styles.sectionTitle}>
              Tác vụ tạm dừng:{' '}
              {pausedTransferData.type === 'upload' ? 'Tải lên' : 'Tải xuống'}
            </Text>
            <Text style={styles.fileInfo}>
              {pausedTransferData.type === 'upload'
                ? `Tải lên: ${pausedTransferData.remotePath.split('/').pop()}`
                : `Tải xuống: ${pausedTransferData.remotePath
                    .split('/')
                    .pop()}`}
            </Text>

            <View style={styles.pausedActions}>
              <TouchableOpacity
                style={styles.resumeButton}
                onPress={resumeTask}
              >
                <Text style={styles.buttonText}>Tiếp tục</Text>
              </TouchableOpacity>

              <TouchableOpacity
                style={styles.cancelButton}
                onPress={cancelPausedTask}
              >
                <Text style={styles.buttonText}>Hủy</Text>
              </TouchableOpacity>
            </View>
          </View>
        )}

        {/* Hiển thị trạng thái */}
        <View style={styles.section}>
          <Text style={styles.sectionTitle}>Trạng thái</Text>
          <Text style={styles.statusMessage}>{status}</Text>
        </View>
      </ScrollView>

      {/* Modal tạo thư mục mới */}
      <Modal
        animationType="slide"
        transparent={true}
        visible={showNewDirModal}
        onRequestClose={() => setShowNewDirModal(false)}
      >
        <View style={styles.modalContainer}>
          <View style={styles.modalContent}>
            <Text style={styles.modalTitle}>Tạo thư mục mới</Text>
            <TextInput
              style={styles.modalInput}
              placeholder="Tên thư mục"
              value={newDirName}
              onChangeText={setNewDirName}
              autoFocus
            />
            <View style={styles.modalButtons}>
              <TouchableOpacity
                style={styles.modalButton}
                onPress={() => setShowNewDirModal(false)}
              >
                <Text style={styles.modalButtonText}>Hủy</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={styles.modalButtonPrimary}
                onPress={createDirectory}
              >
                <Text style={styles.modalButtonText}>Tạo</Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>

      {/* Modal đổi tên */}
      <Modal
        animationType="slide"
        transparent={true}
        visible={renameItem !== null}
        onRequestClose={() => setRenameItem(null)}
      >
        <View style={styles.modalContainer}>
          <View style={styles.modalContent}>
            <Text style={styles.modalTitle}>
              Đổi tên {renameItem?.isDir ? 'thư mục' : 'tệp tin'}
            </Text>
            <Text style={styles.modalSubtitle}>
              Tên hiện tại: {renameItem?.name}
            </Text>
            <TextInput
              style={styles.modalInput}
              placeholder="Tên mới"
              value={newFileName}
              onChangeText={setNewFileName}
              autoFocus
            />
            <View style={styles.modalButtons}>
              <TouchableOpacity
                style={styles.modalButton}
                onPress={() => {
                  setRenameItem(null);
                  setNewFileName('');
                }}
              >
                <Text style={styles.modalButtonText}>Hủy</Text>
              </TouchableOpacity>
              <TouchableOpacity
                style={styles.modalButtonPrimary}
                onPress={renameFileOrDir}
              >
                <Text style={styles.modalButtonText}>Đổi tên</Text>
              </TouchableOpacity>
            </View>
          </View>
        </View>
      </Modal>
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#f0f0f0',
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: 16,
    backgroundColor: '#ffffff',
    borderBottomWidth: 1,
    borderBottomColor: '#e0e0e0',
  },
  headerTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    color: '#333',
  },
  statusIndicator: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  statusDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    marginRight: 6,
  },
  connectedDot: {
    backgroundColor: '#4CAF50',
  },
  disconnectedDot: {
    backgroundColor: '#F44336',
  },
  statusText: {
    fontSize: 12,
    color: '#666',
  },
  scrollView: {
    flex: 1,
  },
  section: {
    backgroundColor: '#ffffff',
    borderRadius: 8,
    margin: 8,
    padding: 16,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 1 },
    shadowOpacity: 0.1,
    shadowRadius: 2,
    elevation: 2,
  },
  sectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    marginBottom: 8,
  },
  sectionTitle: {
    fontSize: 16,
    fontWeight: 'bold',
    marginBottom: 8,
  },
  actionsContainer: {
    flexDirection: 'row',
  },
  actionButton: {
    marginLeft: 8,
    paddingVertical: 4,
    paddingHorizontal: 8,
    backgroundColor: '#f0f0f0',
    borderRadius: 4,
  },
  actionButtonText: {
    fontSize: 12,
    color: '#333',
  },
  input: {
    backgroundColor: '#f7f7f7',
    borderWidth: 1,
    borderColor: '#e0e0e0',
    borderRadius: 4,
    padding: 10,
    marginBottom: 8,
    color: 'black',
  },
  buttonContainer: {
    marginTop: 8,
  },
  primaryButton: {
    backgroundColor: '#2196F3',
    borderRadius: 4,
    padding: 12,
    alignItems: 'center',
  },
  secondaryButton: {
    backgroundColor: '#FF5722',
    borderRadius: 4,
    padding: 12,
    alignItems: 'center',
  },
  buttonText: {
    color: '#ffffff',
    fontWeight: 'bold',
  },
  pathContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: '#ffffff',
    padding: 8,
    marginHorizontal: 8,
    borderRadius: 4,
  },
  navButtons: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  navButton: {
    padding: 8,
    borderRadius: 4,
    backgroundColor: '#f0f0f0',
  },
  disabledButton: {
    backgroundColor: '#aaa',
  },
  navButtonText: {
    fontSize: 16,
    fontWeight: 'bold',
  },
  disabledText: {
    color: '#aaa',
  },
  breadcrumbContainer: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  breadcrumbItem: {
    padding: 8,
    borderRadius: 4,
    backgroundColor: '#f0f0f0',
  },
  breadcrumbText: {
    fontSize: 14,
    color: '#333',
  },
  breadcrumbSeparator: {
    marginHorizontal: 8,
    color: '#666',
  },
  historyButton: {
    padding: 8,
    borderRadius: 4,
    backgroundColor: '#f0f0f0',
  },
  historyButtonText: {
    fontSize: 16,
    fontWeight: 'bold',
  },
  historyMenu: {
    backgroundColor: '#ffffff',
    padding: 16,
    borderRadius: 8,
  },
  historyMenuTitle: {
    fontSize: 16,
    fontWeight: 'bold',
    marginBottom: 8,
  },
  historyMenuItem: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 8,
  },
  historyMenuItemIcon: {
    fontSize: 16,
    marginRight: 8,
  },
  historyMenuItemText: {
    fontSize: 14,
    color: '#333',
  },
  emptyHistoryText: {
    textAlign: 'center',
    color: '#999',
    marginTop: 16,
    marginBottom: 8,
  },
  emptyDirectoryContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 16,
  },
  emptyDirectoryIcon: {
    fontSize: 48,
    marginBottom: 16,
  },
  emptyDirectoryTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 8,
  },
  emptyMessage: {
    textAlign: 'center',
    color: '#666',
    marginBottom: 20,
  },
  emptyDirCreateButton: {
    backgroundColor: '#2196F3',
    borderRadius: 4,
    padding: 12,
    alignItems: 'center',
    marginTop: 16,
  },
  emptyDirCreateButtonText: {
    color: '#ffffff',
    fontWeight: 'bold',
  },
  progressContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: 8,
  },
  progressBackground: {
    flex: 1,
    height: 10,
    backgroundColor: '#e0e0e0',
    borderRadius: 5,
    overflow: 'hidden',
  },
  progressFill: {
    height: '100%',
    backgroundColor: '#4CAF50',
  },
  progressText: {
    marginLeft: 8,
    fontSize: 12,
    color: '#666',
    width: 40,
    textAlign: 'right',
  },
  statusMessage: {
    color: '#666',
  },
  modalContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: 'rgba(0, 0, 0, 0.5)',
  },
  modalContent: {
    width: '80%',
    backgroundColor: 'white',
    borderRadius: 10,
    padding: 20,
    alignItems: 'center',
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 2,
    },
    shadowOpacity: 0.25,
    shadowRadius: 3.84,
    elevation: 5,
  },
  modalTitle: {
    fontSize: 18,
    fontWeight: 'bold',
    marginBottom: 15,
  },
  modalSubtitle: {
    fontSize: 14,
    color: '#666',
    marginBottom: 10,
  },
  modalInput: {
    width: '100%',
    borderWidth: 1,
    borderColor: '#ccc',
    borderRadius: 5,
    padding: 10,
    marginBottom: 15,
    color: 'black',
  },
  modalButtons: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    width: '100%',
  },
  modalButton: {
    padding: 10,
    borderRadius: 5,
    backgroundColor: '#ddd',
    width: '45%',
    alignItems: 'center',
  },
  modalButtonPrimary: {
    padding: 10,
    borderRadius: 5,
    backgroundColor: '#007BFF',
    width: '45%',
    alignItems: 'center',
  },
  modalButtonText: {
    color: '#fff',
    fontWeight: 'bold',
  },
  infoBox: {
    backgroundColor: '#e3f2fd',
    padding: 12,
    margin: 8,
    borderRadius: 8,
    borderLeftWidth: 4,
    borderLeftColor: '#2196F3',
  },
  infoTitle: {
    fontWeight: 'bold',
    marginBottom: 4,
    color: '#0d47a1',
  },
  infoText: {
    fontSize: 12,
    color: '#333',
    marginBottom: 2,
  },
  pauseButton: {
    backgroundColor: '#FF9800',
    borderRadius: 4,
    padding: 8,
    alignItems: 'center',
    marginTop: 8,
  },
  pauseButtonText: {
    color: '#ffffff',
    fontWeight: 'bold',
  },
  pausedActions: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: 8,
  },
  resumeButton: {
    backgroundColor: '#4CAF50',
    borderRadius: 4,
    padding: 8,
    flex: 1,
    alignItems: 'center',
    marginRight: 4,
  },
  cancelButton: {
    backgroundColor: '#F44336',
    borderRadius: 4,
    padding: 8,
    flex: 1,
    alignItems: 'center',
    marginLeft: 4,
  },
  fileList: {
    marginTop: 8,
  },
  fileItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    borderBottomWidth: 1,
    borderBottomColor: '#efefef',
    paddingVertical: 8,
  },
  fileButton: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
  },
  fileIcon: {
    fontSize: 24,
    marginRight: 8,
  },
  folderIcon: {
    color: '#2196F3',
  },
  docIcon: {
    color: '#FF5722',
  },
  fileDetails: {
    flex: 1,
  },
  fileName: {
    fontSize: 14,
    color: '#333',
  },
  fileInfo: {
    fontSize: 12,
    color: '#999',
  },
  deleteButton: {
    backgroundColor: '#ffebee',
    borderRadius: 4,
    paddingVertical: 4,
    paddingHorizontal: 8,
  },
  deleteButtonText: {
    color: '#F44336',
    fontSize: 12,
  },
  openButton: {
    backgroundColor: '#2196F3',
    borderRadius: 4,
    paddingVertical: 4,
    paddingHorizontal: 8,
    alignItems: 'center',
  },
  openButtonText: {
    color: '#ffffff',
    fontSize: 12,
    fontWeight: 'bold',
  },
  actionIconButton: {
    paddingVertical: 4,
    paddingHorizontal: 8,
    borderRadius: 4,
    backgroundColor: '#4CAF50',
  },
  actionIconText: {
    fontSize: 12,
    color: '#ffffff',
    fontWeight: 'bold',
  },
  fileActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
});
