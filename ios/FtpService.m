#import "FtpService.h"
#import "LxFTPRequest.h"
#import <sys/dirent.h>

NSString* const FTP_PROGRESS_EVENT_NAME = @"Progress";

NSString* const FTP_ERROR_CODE_LIST = @"FTP_ERROR_CODE_LIST";
NSString* const FTP_ERROR_CODE_UPLOAD = @"FTP_ERROR_CODE_UPLOAD";
NSString* const FTP_ERROR_CODE_CANCELUPLOAD = @"FTP_ERROR_CODE_CANCELUPLOAD";
NSString* const FTP_ERROR_CODE_REMOVE = @"FTP_ERROR_CODE_REMOVE";
NSString* const FTP_ERROR_CODE_DOWNLOAD = @"FTP_ERROR_CODE_DOWNLOAD";
NSString* const FTP_ERROR_CODE_MKDIR = @"FTP_ERROR_CODE_MKDIR";
NSString* const FTP_ERROR_CODE_RENAME = @"FTP_ERROR_CODE_RENAME";

NSInteger const MAX_UPLOAD_COUNT = 10;
NSInteger const MAX_DOWNLOAD_COUNT = 10;

NSString* const ERROR_MESSAGE_CANCELLED = @"ERROR_MESSAGE_CANCELLED";

#define MAX_PATH_LENGTH 1024
#define MAX_DIRECTORY_DEPTH 50
#define FTP_REQUEST_TIMEOUT 30.0
#define MAX_RETRY_COUNT 3

#pragma mark - FTPTaskData
@interface FTPTaskData:NSObject
@property(readwrite) NSInteger lastPercentage;
@property(readwrite, strong) LxFTPRequest *request;
@end

@implementation FTPTaskData
@end

#pragma mark - MKDirHelper
@interface MKDirHelper : NSObject

@property (nonatomic, strong) NSString *baseURL;
@property (nonatomic, strong) NSString *username;
@property (nonatomic, strong) NSString *password;
@property (nonatomic, copy) RCTPromiseResolveBlock resolver;
@property (nonatomic, copy) RCTPromiseRejectBlock rejecter;

- (instancetype)initWithURL:(NSString *)url
                   username:(NSString *)username
                   password:(NSString *)password
                   resolver:(RCTPromiseResolveBlock)resolver
                   rejecter:(RCTPromiseRejectBlock)rejecter;

- (void)createDirectoriesWithComponents:(NSArray<NSString *> *)components;

@end

@implementation MKDirHelper

- (instancetype)initWithURL:(NSString *)url
                   username:(NSString *)username
                   password:(NSString *)password
                   resolver:(RCTPromiseResolveBlock)resolver
                   rejecter:(RCTPromiseRejectBlock)rejecter {
    if (self = [super init]) {
        _baseURL = url;
        _username = username;
        _password = password;
        _resolver = resolver;
        _rejecter = rejecter;
    }
    return self;
}

- (void)createDirectoriesWithComponents:(NSArray<NSString *> *)components {
    [self createNextDirectoryWithComponents:components currentIndex:0 createdPath:@""];
}

- (void)createNextDirectoryWithComponents:(NSArray<NSString *> *)components 
                           currentIndex:(NSUInteger)index 
                            createdPath:(NSString *)path {
    // Nếu đã tạo xong tất cả các thành phần thì thành công
    if (index >= components.count) {
        self.resolver(@YES);
        return;
    }
    
    // Tạo đường dẫn hiện tại
    NSMutableString *currentPath = [NSMutableString stringWithString:path];
    [currentPath appendString:components[index]];
    [currentPath appendString:@"/"];
    
    // Chuẩn hóa đường dẫn
    NSString *normalizedPath = [self encodePath:currentPath];
    NSURL *serverURL = [[NSURL URLWithString:self.baseURL] URLByAppendingPathComponent:normalizedPath];
    
    if (!serverURL) {
        self.rejecter(FTP_ERROR_CODE_MKDIR, 
                     [NSString stringWithFormat:@"Invalid server URL with path: %@", normalizedPath], 
                     nil);
        return;
    }
    
    NSLog(@"[FTP] Creating directory: %@", normalizedPath);
    
    // Tạo request
    LxFTPRequest *request = [LxFTPRequest makeDirectoryRequest];
    request.timeoutInterval = FTP_REQUEST_TIMEOUT;
    request.maxRetryCount = MAX_RETRY_COUNT;
    request.serverURL = serverURL;
    request.username = self.username;
    request.password = self.password;
    
    __block NSInteger retryCount = 0;
    __weak MKDirHelper *weakSelf = self;
    
    // Định nghĩa hàm bắt đầu request
    __block void (^startRequest)(void);
    startRequest = ^{
        request.successAction = ^(Class resultClass, id result) {
            NSLog(@"[FTP] Directory created successfully: %@", currentPath);
            // Tiếp tục với thành phần tiếp theo
            [weakSelf createNextDirectoryWithComponents:components 
                                          currentIndex:(index + 1) 
                                           createdPath:currentPath];
        };
        
        request.failAction = ^(CFStreamErrorDomain domain, NSInteger error, NSString *errorMessage) {
            NSLog(@"[FTP] Failed to create directory (domain=%ld, error=%ld): %@", 
                  (long)domain, (long)error, errorMessage);
            
            // Nếu thư mục đã tồn tại, tiếp tục với thành phần tiếp theo
            if ((domain == kCFStreamErrorDomainPOSIX && error == EEXIST) || 
                (domain == kCFStreamErrorDomainCustom && error == 550)) {
                NSLog(@"[FTP] Directory already exists, continuing: %@", currentPath);
                [weakSelf createNextDirectoryWithComponents:components 
                                              currentIndex:(index + 1) 
                                               createdPath:currentPath];
                return;
            }
            
            // Xử lý các lỗi cần thử lại
            BOOL isRetryableError = (domain == kCFStreamErrorDomainPOSIX && 
                                     (error == ETIMEDOUT || error == ECONNREFUSED));
            
            if (isRetryableError && retryCount < MAX_RETRY_COUNT) {
                retryCount++;
                NSLog(@"[FTP] Retrying make directory operation (attempt %ld/%d)", 
                      (long)retryCount, MAX_RETRY_COUNT);
                startRequest();
                return;
            }
            
            // Xử lý các lỗi khác
            NSString *message = errorMessage ?: @"Unknown error";
            
            if (domain == kCFStreamErrorDomainPOSIX) {
                switch (error) {
                    case EACCES:
                        message = @"Permission denied - insufficient privileges";
                        break;
                    case ENOENT:
                        message = @"Parent directory does not exist";
                        break;
                    default:
                        break;
                }
            }
            
            NSString *errorCode = FTP_ERROR_CODE_MKDIR;
            NSError *nsError = [self makeErrorFromDomain:domain 
                                               errorCode:error 
                                           errorMessage:message];
            weakSelf.rejecter(errorCode, message, nsError);
        };
        
        BOOL started = [request start];
        if (!started) {
            weakSelf.rejecter(FTP_ERROR_CODE_MKDIR, @"Failed to start make directory operation", nil);
        }
    };
    
    startRequest();
}

// Triển khai lại các phương thức tiện ích cần thiết
- (NSString *)encodePath:(NSString *)path {
    // Xóa nhiều dấu gạch chéo liên tiếp
    NSString *sanitized = [path stringByReplacingOccurrencesOfString:@"//" 
                                                          withString:@"/" 
                                                             options:NSRegularExpressionSearch 
                                                               range:NSMakeRange(0, [path length])];
    
    // Cắt bỏ khoảng trắng
    sanitized = [sanitized stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    // Xóa dấu gạch chéo đầu
    if ([sanitized hasPrefix:@"/"]) {
        sanitized = [sanitized substringFromIndex:1];
    }
    
    // Tạo một character set bao gồm các ký tự an toàn cho đường dẫn FTP
    NSMutableCharacterSet *allowedChars = [[NSCharacterSet URLPathAllowedCharacterSet] mutableCopy];
    // Thêm các ký tự an toàn cho đường dẫn FTP
    NSString *additionalChars = @"[]{}()!@#$%^&*_+-=,.;'~`";
    for (NSUInteger i = 0; i < [additionalChars length]; i++) {
        [allowedChars addCharactersInRange:NSMakeRange([additionalChars characterAtIndex:i], 1)];
    }
    
    // Mã hóa URL cho đường dẫn
    NSString *encoded = [sanitized stringByAddingPercentEncodingWithAllowedCharacters:allowedChars];
    
    return encoded;
}

- (NSError *)makeErrorFromDomain:(CFStreamErrorDomain)domain 
                       errorCode:(NSInteger)error 
                   errorMessage:(NSString *)errorMessage {
    NSErrorDomain nsDomain = NSCocoaErrorDomain;
    switch (domain) {
        case kCFStreamErrorDomainCustom:
            nsDomain = NSCocoaErrorDomain;
            break;
        case kCFStreamErrorDomainPOSIX:
            nsDomain = NSPOSIXErrorDomain;
            break;
        case kCFStreamErrorDomainMacOSStatus:
            nsDomain = NSOSStatusErrorDomain;
            break;
    }
    return [NSError errorWithDomain:nsDomain 
                               code:error 
                           userInfo:@{NSLocalizedDescriptionKey:errorMessage}];
}

@end

#pragma mark - FtpService
@implementation FtpService {
    NSString* url;
    NSString* user;
    NSString* password;
    NSMutableDictionary* uploadTokens;
    bool hasListeners;
    NSMutableDictionary* downloadTokens;
}

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

 - (instancetype)init {
     if (self = [super init]) {
         // Initialize self
         self->uploadTokens = [[NSMutableDictionary alloc]initWithCapacity:MAX_UPLOAD_COUNT];
         self->downloadTokens = [[NSMutableDictionary alloc]initWithCapacity:MAX_DOWNLOAD_COUNT];
     }
     return self;
 }
+ (BOOL)requiresMainQueueSetup
{
  return NO;  // only do this if your module initialization relies on calling UIKit!
}
RCT_EXPORT_MODULE(FtpService)

-(void)startObserving {
    hasListeners = YES;
}

-(void)stopObserving {
    hasListeners = NO;
}

- (NSArray<NSString *> *)supportedEvents
{
  return @[FTP_PROGRESS_EVENT_NAME];
}

- (void)sendProgressEventToToken:(NSString*) token withPercentage:(NSInteger )percentage
{
    if (hasListeners) { // Only send events if anyone is listening
        NSLog(@"send percentage %ld",percentage);
        [self sendEventWithName:FTP_PROGRESS_EVENT_NAME body:@{@"token":token, @"percentage": @(percentage)}];
    }
}

- (void)sendUploadProgressEventToToken:(NSString*) token withPercentage:(NSInteger )percentage
{
    FTPTaskData* upload = self->uploadTokens[token];
    if(percentage == upload.lastPercentage){
        NSLog(@"the percentage is same %ld",percentage);
        return;
    }
    upload.lastPercentage = percentage;
    [self sendProgressEventToToken:token withPercentage:percentage];
}
- (void)sendDownloadProgressEventToToken:(NSString*) token withPercentage:(NSInteger )percentage
{
    FTPTaskData* download = self->downloadTokens[token];
    if(percentage == download.lastPercentage){
        NSLog(@"the percentage is same %ld",percentage);
        return;
    }
    download.lastPercentage = percentage;
    [self sendProgressEventToToken:token withPercentage:percentage];
}
-(NSError*) makeErrorFromDomain:(CFStreamErrorDomain) domain errorCode:( NSInteger) error errorMessage:(NSString *)errorMessage
{
    NSErrorDomain nsDomain = NSCocoaErrorDomain;
    switch (domain){
        case kCFStreamErrorDomainCustom:
            nsDomain = NSCocoaErrorDomain;
            break;
        case kCFStreamErrorDomainPOSIX:
            nsDomain = NSPOSIXErrorDomain;
            break;
        case kCFStreamErrorDomainMacOSStatus:
            nsDomain = NSOSStatusErrorDomain;
            break;
    }
    return [NSError errorWithDomain:nsDomain code:error userInfo:@{NSLocalizedDescriptionKey:errorMessage}];
}

-(NSString*) makeErrorMessageWithPrefix:(NSString*) prefix domain:(CFStreamErrorDomain) domain errorCode:( NSInteger) error errorMessage:(NSString *)errorMessage
{
    // Trả về thông báo lỗi người dùng trực tiếp mà không bao gồm thông tin kỹ thuật phức tạp
    if (!errorMessage || [errorMessage length] == 0) {
        // Nếu không có thông báo lỗi, tạo thông báo dựa trên domain và mã lỗi
        switch (domain) {
            case kCFStreamErrorDomainCustom:
                switch (error) {
                    case 550:
                        return @"Thư mục không tồn tại hoặc không có quyền truy cập";
                    case 530:
                        return @"Không thể đăng nhập, kiểm tra lại tên người dùng và mật khẩu";
                    case 421:
                        return @"Kết nối FTP không khả dụng, máy chủ đã đóng kết nối";
                    case 425:
                        return @"Không thể mở kết nối dữ liệu";
                    case 426:
                        return @"Kết nối bị đóng, quá trình bị hủy bỏ";
                    case 450:
                        return @"Thao tác không được thực hiện, tệp có thể đang được sử dụng";
                    case 451:
                        return @"Thao tác bị hủy bỏ, lỗi xử lý";
                    case 452:
                        return @"Thao tác không được thực hiện, không đủ dung lượng lưu trữ";
                    default:
                        return [NSString stringWithFormat:@"Lỗi FTP %ld", (long)error];
                }
                break;
            case kCFStreamErrorDomainPOSIX:
                return [NSString stringWithUTF8String:strerror((int)error)];
            case kCFStreamErrorDomainMacOSStatus:
                return [NSString stringWithFormat:@"Lỗi hệ thống %ld", (long)error];
            default:
                return [NSString stringWithFormat:@"Lỗi không xác định %ld", (long)error];
        }
    }
    
    // Sử dụng thông báo lỗi đã cung cấp
    return errorMessage;
}

RCT_REMAP_METHOD(setup,
                 setupWithIp:(NSString*) ip
                 AndPort:(NSInteger) port
                 AndUserName:(NSString*) userName
                 AndPassword:(NSString*) password)
{
    self->url = [NSString stringWithFormat:@"ftp://%@:%ld", ip, (long)port ];
    self->user = userName;
    self->password = password;
}

-(NSString*) typeStringFromType:(NSInteger) type
{
    // iOS FTP value 4 corresponds to a directory (standard)
    if (type == 4) {
        return @"directory";
    }
    // Các giá trị khác có thể tùy thuộc vào máy chủ FTP
    else if (type == 8 || type == 0) {
        return @"file";
    } 
    else {
        switch (type) {
            case DT_DIR:
                return @"directory";
            case DT_REG:
                return @"file";
            case DT_LNK:
                return @"link";
            default:
                break;
        }
    }
    return @"unknown";
}
-(NSString*) ISO8601StringFromNSDate:(NSDate*) date
{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    NSLocale *enUSPOSIXLocale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    [dateFormatter setLocale:enUSPOSIXLocale];
    [dateFormatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ssZZZZZ"];
    [dateFormatter setCalendar:[NSCalendar calendarWithIdentifier:NSCalendarIdentifierGregorian]];

    return [dateFormatter stringFromDate:date];
}

RCT_REMAP_METHOD(list,
                 listRemotePath:(NSString*)remotePath
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
    if (!self->url || self->url.length == 0) {
        reject(FTP_ERROR_CODE_LIST, @"FTP server URL is not set. Call setup first.", nil);
        return;
    }
    
    // Validate and sanitize path
    if (![self isValidPath:remotePath]) {
        reject(FTP_ERROR_CODE_LIST, @"Invalid directory path", nil);
        return;
    }
    
    // Ensure proper encoding of the path
    NSString *normalizedPath = [self encodePath:remotePath];
    NSLog(@"[FTP] Listing directory: %@", normalizedPath);
    
    LxFTPRequest *request = [LxFTPRequest resourceListRequest];
    request.timeoutInterval = FTP_REQUEST_TIMEOUT;
    request.maxRetryCount = MAX_RETRY_COUNT;
    
    NSURL *serverURL = [[NSURL URLWithString:self->url] URLByAppendingPathComponent:normalizedPath];
    if (!serverURL) {
        reject(FTP_ERROR_CODE_LIST, [NSString stringWithFormat:@"Invalid server URL with path: %@", normalizedPath], nil);
        return;
    }
    request.serverURL = serverURL;
    request.username = self->user;
    request.password = self->password;

    __block NSInteger retryCount = 0;
    
    void (^startRequest)(void) = ^{
        request.successAction = ^(Class resultClass, id result) {
            NSArray *resultArray = (NSArray *)result;
            NSMutableArray *files = [[NSMutableArray alloc] initWithCapacity:[resultArray count]];
            for (NSDictionary* file in resultArray) {
                NSString* name = file[(__bridge NSString *)kCFFTPResourceName];
                NSInteger type = [file[(__bridge NSString *)kCFFTPResourceType] integerValue];
                NSInteger size = [file[(__bridge NSString *)kCFFTPResourceSize] integerValue];
                NSDate* timestamp = file[(__bridge NSString *)kCFFTPResourceModDate];
                
                // Xác định loại tệp
                NSString* fileType = [self typeStringFromType:type];
                
                // Kiểm tra dấu hiệu bổ sung để phát hiện thư mục
                // 1. Nếu tên kết thúc bằng dấu / thì là thư mục
                if ([name hasSuffix:@"/"]) {
                    fileType = @"directory";
                }
                
                // 2. Nếu kích thước là 0 và loại chưa được xác định rõ
                if (size == 0 && [fileType isEqualToString:@"unknown"]) {
                    // Thường thì thư mục mới tạo có kích thước 0
                    // Đây là phỏng đoán hợp lý khi không có thông tin rõ ràng
                    fileType = @"directory";
                }
                
                // Loại bỏ dấu / cuối trong tên thư mục (nếu có)
                if ([name hasSuffix:@"/"]) {
                    name = [name substringToIndex:[name length] - 1];
                }
                
                NSDictionary* f = @{@"name":name,@"type":fileType,@"size":@(size),@"timestamp":[self ISO8601StringFromNSDate:timestamp]};
                [files addObject:f];
            }
            resolve([files copy]);
        };
        
        request.failAction = ^(CFStreamErrorDomain domain, NSInteger error, NSString *errorMessage) {
            NSLog(@"[FTP] List failed: domain=%ld, error=%ld, message=%@", (long)domain, (long)error, errorMessage);
            
            // Xử lý cụ thể các mã lỗi FTP
            NSString *userFriendlyMessage = errorMessage;
            
            if (domain == kCFStreamErrorDomainCustom) {
                switch (error) {
                    case 550:
                        userFriendlyMessage = [NSString stringWithFormat:@"Thư mục '%@' không tồn tại hoặc không có quyền truy cập", remotePath];
                        break;
                    case 530:
                        userFriendlyMessage = @"Không thể đăng nhập, kiểm tra lại tên người dùng và mật khẩu";
                        break;
                    case 421:
                        userFriendlyMessage = @"Kết nối FTP không khả dụng, máy chủ đã đóng kết nối";
                        break;
                    case 425:
                        userFriendlyMessage = @"Không thể mở kết nối dữ liệu";
                        break;
                    case 426:
                        userFriendlyMessage = @"Kết nối bị đóng, quá trình bị hủy bỏ";
                        break;
                    case 450:
                        userFriendlyMessage = @"Thao tác không được thực hiện, tệp có thể đang được sử dụng";
                        break;
                    case 451:
                        userFriendlyMessage = @"Thao tác bị hủy bỏ, lỗi xử lý";
                        break;
                    case 452:
                        userFriendlyMessage = @"Thao tác không được thực hiện, không đủ dung lượng lưu trữ";
                        break;
                    default:
                        userFriendlyMessage = [NSString stringWithFormat:@"Lỗi FTP %ld: %@", (long)error, errorMessage];
                        break;
                }
            } else if (domain == kCFStreamErrorDomainPOSIX) {
                // Xử lý lỗi POSIX phổ biến
                switch (error) {
                    case ETIMEDOUT:
                        userFriendlyMessage = @"Kết nối hết thời gian chờ";
                        break;
                    case ECONNREFUSED:
                        userFriendlyMessage = @"Kết nối bị từ chối, máy chủ không khả dụng";
                        break;
                    case ENOTCONN:
                        userFriendlyMessage = @"Không có kết nối FTP";
                        break;
                    case ENETDOWN:
                        userFriendlyMessage = @"Mạng không khả dụng";
                        break;
                    case ENETUNREACH:
                        userFriendlyMessage = @"Không thể kết nối đến máy chủ, mạng không thể truy cập";
                        break;
                    default:
                        userFriendlyMessage = [NSString stringWithUTF8String:strerror((int)error)];
                        break;
                }
            }
            
            // Thử lại nếu lỗi có thể khắc phục được
            BOOL isRetryableError = (domain == kCFStreamErrorDomainPOSIX && 
                                    (error == ETIMEDOUT || error == ECONNREFUSED));
            
            if (isRetryableError && retryCount < MAX_RETRY_COUNT) {
                retryCount++;
                NSLog(@"[FTP] Retrying list operation (attempt %ld/%d)", (long)retryCount, MAX_RETRY_COUNT);
                startRequest();
                return;
            }
            
            NSError* nsError = [self makeErrorFromDomain:domain errorCode:error errorMessage:userFriendlyMessage];
            // Sử dụng thông báo lỗi thân thiện trực tiếp, không thêm tiền tố
            reject(FTP_ERROR_CODE_LIST, userFriendlyMessage, nsError);
        };
        
        BOOL started = [request start];
        if (!started) {
            reject(FTP_ERROR_CODE_LIST, @"Failed to start list operation", nil);
        }
    };
    
    startRequest();
}

-(NSString*) makeTokenByLocalPath:(NSString*) localPath andRemotePath:(NSString*) remotePath
{
    return [NSString stringWithFormat:@"%@=>%@",localPath,remotePath ];
}

-(NSString*) getRemotePathFromToken:(NSString*) token
{
    NSArray* tokenParts = [token componentsSeparatedByString:@"=>"];
    if(token && token.length > 1){
        return tokenParts[1];
    }else{
        return nil;
    }
}

- (NSDictionary *)constantsToExport
{
  return @{ ERROR_MESSAGE_CANCELLED: ERROR_MESSAGE_CANCELLED };
}

RCT_REMAP_METHOD(uploadFile,
                 uploadFileFromLocal:(NSString*)localPath
                 toRemote:(NSString*)remotePath
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
    if([[NSFileManager defaultManager] fileExistsAtPath:localPath] == NO)
    {
        reject(FTP_ERROR_CODE_UPLOAD,@"local file is not exist",nil);
        return ;
    }

    // Validate paths
    if (![self isValidPath:remotePath]) {
        reject(FTP_ERROR_CODE_UPLOAD, @"Invalid remote path", nil);
        return;
    }

    NSString* token = [self makeTokenByLocalPath:localPath andRemotePath:remotePath];
    if(self->uploadTokens[token]){
        reject(FTP_ERROR_CODE_UPLOAD,@"same upload is runing",nil);
        return;
    }
    if([self->uploadTokens count] >= MAX_UPLOAD_COUNT){
        reject(FTP_ERROR_CODE_UPLOAD,@"has reach max uploading tasks", nil);
        return;
    }

    LxFTPRequest *request = [LxFTPRequest uploadRequest];
    request.timeoutInterval = FTP_REQUEST_TIMEOUT;
    request.maxRetryCount = MAX_RETRY_COUNT;
    
    NSURL* serverURL = [[NSURL URLWithString:self->url] URLByAppendingPathComponent:[self encodePath:remotePath]];
    request.serverURL = serverURL;
    if (!request.serverURL) {
        reject(FTP_ERROR_CODE_UPLOAD,[NSString stringWithFormat:@"server url is invalide %@",serverURL],nil);
        return;
    }
    NSURL* localFileURL = [NSURL fileURLWithPath:localPath];
    request.localFileURL = localFileURL;
    if (!request.localFileURL) {
        reject(FTP_ERROR_CODE_UPLOAD,[NSString stringWithFormat:@"local url is invalide %@",localFileURL],nil);
        return;
    }

    request.username = self->user;
    request.password = self->password;

    __block NSInteger retryCount = 0;
    
    void (^startRequest)(void) = ^{
        request.progressAction = ^(NSInteger totalSize, NSInteger finishedSize, CGFloat finishedPercent) {
            NSLog(@"totalSize = %ld, finishedSize = %ld, finishedPercent = %f", (long)totalSize, (long)finishedSize, finishedPercent);
            [self sendUploadProgressEventToToken:token withPercentage:finishedPercent];
        };
        
        request.successAction = ^(Class resultClass, id result) {
            NSLog(@"Upload file succcess %@", result);
            [self sendUploadProgressEventToToken:token withPercentage:100];
            [self->uploadTokens removeObjectForKey:token];
            resolve(@(true));
        };
        
        request.failAction = ^(CFStreamErrorDomain domain, NSInteger error, NSString *errorMessage) {
            [self->uploadTokens removeObjectForKey:token];

            NSLog(@"domain = %ld, error = %ld, errorMessage = %@", domain, (long)error, errorMessage);

            if([errorMessage isEqual:ERROR_MESSAGE_CANCELLED]){
                reject(FTP_ERROR_CODE_UPLOAD,ERROR_MESSAGE_CANCELLED,nil);
            }else{
                // Handle retryable errors
                if (retryCount < MAX_RETRY_COUNT && 
                    (domain == kCFStreamErrorDomainPOSIX && 
                     (error == ETIMEDOUT || error == ECONNREFUSED))) {
                    retryCount++;
                    NSLog(@"Retrying upload operation (attempt %ld/%d)", (long)retryCount, MAX_RETRY_COUNT);
                    startRequest();
                    return;
                }
                
                NSError* nsError = [self makeErrorFromDomain:domain errorCode:error errorMessage:errorMessage];
                NSString* message = [self makeErrorMessageWithPrefix:@"upload error" domain:domain errorCode:error errorMessage:errorMessage];
                reject(FTP_ERROR_CODE_UPLOAD,message,nsError);
            }
        };
        
        BOOL started = [request start];
        if(started){
            FTPTaskData* upload = [[FTPTaskData alloc]init];
            upload.lastPercentage = -1;
            upload.request = request;

            [self->uploadTokens setObject:upload forKey:token];
            [self sendUploadProgressEventToToken:token withPercentage:0];
        }else{
            reject(FTP_ERROR_CODE_UPLOAD,@"start uploading failed",nil);
        }
    };
    
    startRequest();
}

-(void) clearRemoteFileByToken:(NSString*) token
{
    NSString* remotePath = [self getRemotePathFromToken:token];
    [self removeWithRemotePath:remotePath resolver:^(id result) {
        NSLog(@"clear remote file %@ success",remotePath);
    } rejecter:^(NSString *code, NSString *message, NSError *error) {
        NSLog(@"clear remote file %@ wrong", message);
    }];
}
RCT_REMAP_METHOD(cancelUploadFile,
                 cancelUploadFileWithToken:(NSString*)token
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
    FTPTaskData* upload = self->uploadTokens[token];

    if(!upload){
        reject(FTP_ERROR_CODE_UPLOAD,@"token is wrong",nil);
        return;
    }
    [self->uploadTokens removeObjectForKey:token];
    [upload.request stop];
    upload.request.failAction(kCFStreamErrorDomainCustom,0,ERROR_MESSAGE_CANCELLED);

    [self clearRemoteFileByToken:token];
    resolve([NSNumber numberWithBool:TRUE]);
}

//remove file or dir
RCT_REMAP_METHOD(remove,
                 removeWithRemotePath:(NSString*)remotePath
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
    LxFTPRequest *request = [LxFTPRequest destoryResourceRequest];
    NSURL* serverURL = [[NSURL URLWithString:self->url] URLByAppendingPathComponent:remotePath];
    request.serverURL = serverURL;
    if (!request.serverURL) {
        reject(FTP_ERROR_CODE_REMOVE,[NSString stringWithFormat:@"server url is invalide %@",serverURL],nil);
        return;
    }
    request.username = self->user;
    request.password = self->password;

    request.successAction = ^(Class resultClass, id result) {
        NSLog(@"Remove file succcess %@", result);
        resolve([NSNumber numberWithBool:TRUE]);
    };
    request.failAction = ^(CFStreamErrorDomain domain, NSInteger error, NSString *errorMessage) {
        NSLog(@"domain = %ld, error = %ld, errorMessage = %@", domain, error, errorMessage);
        NSError* nsError = [self makeErrorFromDomain:domain errorCode:error errorMessage:errorMessage];
        NSString* message = [self makeErrorMessageWithPrefix:@"remove error" domain:domain errorCode:error errorMessage:errorMessage];
        reject(FTP_ERROR_CODE_REMOVE,message,nsError);
    };
    [request start];
}

#pragma mark - Downloading
-(NSString*) makeDownloadTokenByLocalPath:(NSString*) localPath andRemotePath:(NSString*) remotePath
{
    return [NSString stringWithFormat:@"%@<=%@",localPath,remotePath ];
}

-(NSString*) getLocalFilePath:(NSString*) path fromRemotePath:(NSString*) remotePath
{
    if([path hasSuffix:@"/"]){
        NSString* fileName = [remotePath lastPathComponent];
        return [path stringByAppendingPathComponent:fileName];
    }else{
        return path;
    }
}

-(void) clearLocalFileByURL:(NSURL*) localFileURL
{
    [[NSFileManager defaultManager] removeItemAtURL:localFileURL error:nil];
}

RCT_REMAP_METHOD(downloadFile,
                 downloadFileToLocal:(NSString*)localPath
                 fromRemote:(NSString*)remotePath
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
    NSLog(@"downloadFile %@<=%@",localPath,remotePath);
    
    // Validate paths
    if (![self isValidPath:remotePath]) {
        reject(FTP_ERROR_CODE_DOWNLOAD, @"Invalid remote path", nil);
        return;
    }
    
    if (![self isValidPath:localPath]) {
        reject(FTP_ERROR_CODE_DOWNLOAD, @"Invalid local path", nil);
        return;
    }
    
    NSString* token = [self makeDownloadTokenByLocalPath:localPath andRemotePath:remotePath];
    if(self->downloadTokens[token]){
        reject(FTP_ERROR_CODE_DOWNLOAD,@"same download is runing",nil);
        return;
    }
    if([self->downloadTokens count] >= MAX_DOWNLOAD_COUNT){
        reject(FTP_ERROR_CODE_DOWNLOAD,@"has reach max downloading tasks", nil);
        return;
    }
    if([remotePath hasSuffix:@"/"]){
        reject(FTP_ERROR_CODE_DOWNLOAD,@"remote path can not be a dir", nil);
        return;
    }

    NSString* localFilePath = [self getLocalFilePath:localPath fromRemotePath:remotePath];
    if([[NSFileManager defaultManager] fileExistsAtPath:localFilePath] == YES)
    {
        reject(FTP_ERROR_CODE_DOWNLOAD,@"local file is exist",nil);
        return ;
    }
    
    LxFTPRequest *request = [LxFTPRequest downloadRequest];
    request.timeoutInterval = FTP_REQUEST_TIMEOUT;
    request.maxRetryCount = MAX_RETRY_COUNT;
    
    NSURL* serverURL = [[NSURL URLWithString:self->url] URLByAppendingPathComponent:[self encodePath:remotePath]];
    request.serverURL = serverURL;
    if (!request.serverURL) {
        reject(FTP_ERROR_CODE_DOWNLOAD,[NSString stringWithFormat:@"server url is invalide %@",serverURL],nil);
        return;
    }
    NSURL* localFileURL = [NSURL fileURLWithPath:localFilePath];
    request.localFileURL = localFileURL;
    if (!request.localFileURL) {
        reject(FTP_ERROR_CODE_DOWNLOAD,[NSString stringWithFormat:@"local url is invalide %@",localFileURL],nil);
        return;
    }

    request.username = self->user;
    request.password = self->password;

    __block NSInteger retryCount = 0;
    
    void (^startRequest)(void) = ^{
        request.progressAction = ^(NSInteger totalSize, NSInteger finishedSize, CGFloat finishedPercent) {
            NSLog(@"totalSize = %ld, finishedSize = %ld, finishedPercent = %f", (long)totalSize, (long)finishedSize, finishedPercent);
            [self sendDownloadProgressEventToToken:token withPercentage:finishedPercent];
        };
        
        request.successAction = ^(Class resultClass, id result) {
            NSLog(@"Download file succcess %@", result);
            [self sendDownloadProgressEventToToken:token withPercentage:100];
            [self->downloadTokens removeObjectForKey:token];
            resolve(@(true));
        };
        
        request.failAction = ^(CFStreamErrorDomain domain, NSInteger error, NSString *errorMessage) {
            [self->downloadTokens removeObjectForKey:token];

            NSLog(@"domain = %ld, error = %ld, errorMessage = %@", domain, (long)error, errorMessage);

            if([errorMessage isEqual:ERROR_MESSAGE_CANCELLED]){
                reject(FTP_ERROR_CODE_DOWNLOAD,ERROR_MESSAGE_CANCELLED,nil);
            }else{
                // Handle retryable errors
                if (retryCount < MAX_RETRY_COUNT && 
                    (domain == kCFStreamErrorDomainPOSIX && 
                     (error == ETIMEDOUT || error == ECONNREFUSED))) {
                    retryCount++;
                    NSLog(@"Retrying download operation (attempt %ld/%d)", (long)retryCount, MAX_RETRY_COUNT);
                    startRequest();
                    return;
                }
                
                NSError* nsError = [self makeErrorFromDomain:domain errorCode:error errorMessage:errorMessage];
                NSString* message = [self makeErrorMessageWithPrefix:@"download error" domain:domain errorCode:error errorMessage:errorMessage];
                reject(FTP_ERROR_CODE_DOWNLOAD,message,nsError);
            }
            [self clearLocalFileByURL:localFileURL];
        };
        
        BOOL started = [request start];
        if(started){
            FTPTaskData* download = [[FTPTaskData alloc]init];
            download.lastPercentage = -1;
            download.request = request;

            [self->downloadTokens setObject:download forKey:token];
            [self sendDownloadProgressEventToToken:token withPercentage:0];
        }else{
            reject(FTP_ERROR_CODE_DOWNLOAD,@"start download failed",nil);
        }
    };
    
    startRequest();
}

RCT_REMAP_METHOD(cancelDownloadFile,
                 cancelDownloadFileWithToken:(NSString*)token
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
    FTPTaskData* task = self->downloadTokens[token];

    if(!task){
        reject(FTP_ERROR_CODE_DOWNLOAD,@"token is wrong",nil);
        return;
    }
    [self->downloadTokens removeObjectForKey:token];
    [task.request stop];
    task.request.failAction(kCFStreamErrorDomainCustom,0,ERROR_MESSAGE_CANCELLED);

    resolve([NSNumber numberWithBool:TRUE]);
}

-(BOOL)isValidPath:(NSString *)path {
    // Check path length
    if (path.length > MAX_PATH_LENGTH) {
        return NO;
    }
    
    // Check for directory traversal attempts
    if ([path containsString:@".."] || [path containsString:@"./"] || [path containsString:@"../"]) {
        return NO;
    }
    
    // Check for multiple consecutive slashes
    if ([path containsString:@"//"]) {
        return NO;
    }
    
    // Check directory depth
    NSArray *components = [path componentsSeparatedByString:@"/"];
    if (components.count > MAX_DIRECTORY_DEPTH) {
        return NO;
    }
    
    // Check for invalid characters
    NSCharacterSet *invalidChars = [NSCharacterSet characterSetWithCharactersInString:@"\\:*?\"<>|"];
    if ([path rangeOfCharacterFromSet:invalidChars].location != NSNotFound) {
        return NO;
    }
    
    return YES;
}

-(NSString *)sanitizePath:(NSString *)path {
    // Remove multiple consecutive slashes
    NSString *sanitized = [path stringByReplacingOccurrencesOfString:@"//+" withString:@"/" options:NSRegularExpressionSearch range:NSMakeRange(0, [path length])];
    
    // Remove leading/trailing slashes and whitespace
    sanitized = [sanitized stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ([sanitized hasPrefix:@"/"]) {
        sanitized = [sanitized substringFromIndex:1];
    }
    if ([sanitized hasSuffix:@"/"]) {
        sanitized = [sanitized substringToIndex:sanitized.length - 1];
    }
    
    return sanitized;
}

-(NSString *)encodePath:(NSString *)path {
    // First sanitize the path but preserve trailing slash for directories
    NSString *sanitized = path;
    
    // Remove multiple consecutive slashes
    sanitized = [sanitized stringByReplacingOccurrencesOfString:@"//" withString:@"/" options:NSRegularExpressionSearch range:NSMakeRange(0, [sanitized length])];
    
    // Trim whitespace
    sanitized = [sanitized stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    
    // Remove leading slash
    if ([sanitized hasPrefix:@"/"]) {
        sanitized = [sanitized substringFromIndex:1];
    }
    
    // Note: We specifically don't remove trailing slash as it may be significant for directories
    
    // Create a custom character set that includes more characters than URLPathAllowedCharacterSet
    NSMutableCharacterSet *allowedChars = [[NSCharacterSet URLPathAllowedCharacterSet] mutableCopy];
    // Add additional safe characters for FTP paths
    NSString *additionalChars = @"[]{}()!@#$%^&*_+-=,.;'~`";
    for (NSUInteger i = 0; i < [additionalChars length]; i++) {
        [allowedChars addCharactersInRange:NSMakeRange([additionalChars characterAtIndex:i], 1)];
    }
    
    // URL encode the path
    NSString *encoded = [sanitized stringByAddingPercentEncodingWithAllowedCharacters:allowedChars];
    
    return encoded;
}

RCT_REMAP_METHOD(makeDirectory,
                 makeDirectory:(NSString *)remotePath
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
    if (!self->url || self->url.length == 0) {
        reject(FTP_ERROR_CODE_MKDIR, @"FTP server URL is not set. Call setup first.", nil);
        return;
    }
    
    if (!remotePath || remotePath.length == 0) {
        reject(FTP_ERROR_CODE_MKDIR, @"Directory path cannot be empty", nil);
        return;
    }
    
    // Validate and sanitize path
    if (![self isValidPath:remotePath]) {
        reject(FTP_ERROR_CODE_MKDIR, @"Invalid directory path", nil);
        return;
    }
    
    // Ensure path ends with /
    if (![remotePath hasSuffix:@"/"]) {
        remotePath = [remotePath stringByAppendingString:@"/"];
    }
    
    NSString *normalizedPath = [self encodePath:remotePath];
    NSLog(@"[FTP] Creating directory: %@", normalizedPath);
    
    // Extract parent directories to check if we need to create them
    NSArray *pathComponents = [remotePath componentsSeparatedByString:@"/"];
    pathComponents = [pathComponents filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    
    // If there are no path components (trying to create root), just resolve
    if (pathComponents.count == 0) {
        resolve(@YES);
        return;
    }
    
    // Giữ tham chiếu mạnh đến recursive block
    __block NSMutableArray *dirsToCreate = [NSMutableArray arrayWithArray:pathComponents];
    
    // Tạo một helper class để tránh retain cycles và tham chiếu yếu
    MKDirHelper *helper = [[MKDirHelper alloc] initWithURL:self->url 
                                                  username:self->user 
                                                  password:self->password 
                                                  resolver:resolve 
                                                  rejecter:reject];
    
    // Bắt đầu quá trình tạo thư mục đệ quy
    [helper createDirectoriesWithComponents:dirsToCreate];
}

RCT_REMAP_METHOD(rename,
                 rename:(NSString*)oldPath
                 to:(NSString*)newPath
                 resolver:(RCTPromiseResolveBlock)resolve
                 rejecter:(RCTPromiseRejectBlock)reject)
{
    if (!self->url || self->url.length == 0) {
        NSLog(@"[FTP_ERROR] Server URL is not set for rename operation");
        reject(FTP_ERROR_CODE_RENAME, @"FTP server URL is not set. Call setup first.", nil);
        return;
    }
    
    if (!oldPath || oldPath.length == 0) {
        NSLog(@"[FTP_ERROR] Source path is empty for rename operation");
        reject(FTP_ERROR_CODE_RENAME, @"Source path cannot be empty", nil);
        return;
    }
    
    if (!newPath || newPath.length == 0) {
        NSLog(@"[FTP_ERROR] Destination path is empty for rename operation");
        reject(FTP_ERROR_CODE_RENAME, @"Destination path cannot be empty", nil);
        return;
    }
    
    // Validate and sanitize paths
    if (![self isValidPath:oldPath] || ![self isValidPath:newPath]) {
        NSLog(@"[FTP_ERROR] Invalid path format for rename: old=%@, new=%@", oldPath, newPath);
        reject(FTP_ERROR_CODE_RENAME, @"Invalid path format", nil);
        return;
    }
    
    // Normalize the paths - encode but preserve trailing slashes
    NSString *normalizedOldPath = [self encodePath:oldPath];
    NSString *normalizedNewPath = [self encodePath:newPath];
    
    NSLog(@"[FTP_DEBUG] Starting rename operation");
    NSLog(@"[FTP_DEBUG] Normalized paths: %@ → %@", normalizedOldPath, normalizedNewPath);
    
    // Create complete URLs
    NSURL *sourceURL = [[NSURL URLWithString:self->url] URLByAppendingPathComponent:normalizedOldPath];
    NSURL *destinationURL = [[NSURL URLWithString:self->url] URLByAppendingPathComponent:normalizedNewPath];
    
    if (!sourceURL || !destinationURL) {
        NSLog(@"[FTP_ERROR] Failed to create valid URLs for the rename operation");
        reject(FTP_ERROR_CODE_RENAME, @"Invalid URL construction", nil);
        return;
    }
    
    // Create and configure the rename request
    LxRenameFTPRequest *request = (LxRenameFTPRequest *)[LxFTPRequest renameRequest];
    request.timeoutInterval = FTP_REQUEST_TIMEOUT;
    request.maxRetryCount = MAX_RETRY_COUNT;
    request.serverURL = sourceURL;
    request.destinationURL = destinationURL;
    request.username = self->user;
    request.password = self->password;

    __block NSInteger retryCount = 0;
    
    void (^startRequest)(void) = ^{
        request.successAction = ^(Class resultClass, id result) {
            NSLog(@"[FTP_DEBUG] Rename operation successful from %@ to %@", normalizedOldPath, normalizedNewPath);
            resolve(@(YES));
        };
        
        request.failAction = ^(CFStreamErrorDomain domain, NSInteger error, NSString *errorMessage) {
            NSLog(@"[FTP_ERROR] Rename failed: domain=%ld, error=%ld, message=%@", (long)domain, (long)error, errorMessage);
            
            // Prepare error details
            NSString *errorCode = FTP_ERROR_CODE_RENAME;
            NSString *message = errorMessage;
            
            // Handle specific error codes
            if (domain == kCFStreamErrorDomainPOSIX) {
                switch (error) {
                    case EACCES:
                        message = @"Permission denied - insufficient privileges";
                        break;
                    case EEXIST:
                        message = @"Destination path already exists";
                        break;
                    case ENOENT:
                        message = @"Source path does not exist";
                        break;
                    case EINVAL:
                        message = @"Invalid path format";
                        break;
                    case ETIMEDOUT:
                        message = @"Operation timed out";
                        break;
                    case ECONNREFUSED:
                        message = @"Connection refused";
                        break;
                    default:
                        // Use the provided error message
                        break;
                }
            } else if (domain == kCFStreamErrorDomainCustom && error == 550) {
                // 550 is "File unavailable" - common for "no such file" or permission issues
                message = @"File unavailable - no such file or permission denied";
            } else if (domain == kCFStreamErrorDomainCustom && error == 553) {
                // 553 is "File name not allowed"
                message = @"File name not allowed";
            }
            
            // Handle retryable errors
            BOOL isRetryableError = (domain == kCFStreamErrorDomainPOSIX && 
                                    (error == ETIMEDOUT || error == ECONNREFUSED));
            
            if (isRetryableError && retryCount < MAX_RETRY_COUNT) {
                retryCount++;
                NSLog(@"[FTP_DEBUG] Retrying rename operation (attempt %ld/%d)", (long)retryCount, MAX_RETRY_COUNT);
                startRequest();
                return;
            }
            
            NSError* nsError = [self makeErrorFromDomain:domain errorCode:error errorMessage:message];
            reject(errorCode, message, nsError);
        };
        
        BOOL started = [request start];
        if (!started) {
            NSLog(@"[FTP_ERROR] Failed to start rename operation");
            reject(FTP_ERROR_CODE_RENAME, @"Failed to start rename operation", nil);
        } else {
            NSLog(@"[FTP_DEBUG] Rename request started successfully");
        }
    };
    
    startRequest();
}
@end
  
