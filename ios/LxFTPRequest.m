#import "LxFTPRequest.h"

// Define FTP stream property constants if not available
#ifndef kCFStreamPropertyFTPCommand
#define kCFStreamPropertyFTPCommand CFSTR("kCFStreamPropertyFTPCommand")
#endif

#ifndef kCFStreamPropertyFTPCommandArgument
#define kCFStreamPropertyFTPCommandArgument CFSTR("kCFStreamPropertyFTPCommandArgument")
#endif

#ifndef kCFStreamPropertyFTPCommandAppendSequence
#define kCFStreamPropertyFTPCommandAppendSequence CFSTR("kCFStreamPropertyFTPCommandAppendSequence")
#endif

#ifndef kCFStreamPropertyFTPCustomCommands
#define kCFStreamPropertyFTPCustomCommands CFSTR("kCFStreamPropertyFTPCustomCommands")
#endif

static NSInteger const RESOURCE_LIST_BUFFER_SIZE = 1024;
static NSInteger const DOWNLOAD_BUFFER_SIZE = 4096;
static NSInteger const UPLOAD_BUFFER_SIZE = 1024;

@implementation NSString (ftp)

- (BOOL)isValidateFTPURLString {
    if (self.length > 0) {
        return [[NSPredicate predicateWithFormat:@"SELF MATCHES %@", @"^[Ff][Tt][Pp]://(\\w*(:[=_0-9a-zA-Z\\$\\(\\)\\*\\+\\-\\.\\[\\]\\?\\\\\\^\\{\\}\\|`~!#%&\'\",<>/]*)?@)?([0-9a-zA-Z\\-]+\\.)+[0-9a-zA-Z]+(:(6553[0-5]|655[0-2]\\d|654\\d\\d|64\\d\\d\\d|[0-5]?\\d?\\d?\\d?\\d))?(/?|((/[=_0-9a-zA-Z\\-%]+)+(/|\\.[_0-9a-zA-Z]+)?))$"] evaluateWithObject:self];
    } else {
        return NO;
    }
}

- (BOOL)isValidateFileURLString {
    if (self.length > 0) {
        return [[NSPredicate predicateWithFormat:@"SELF MATCHES %@", @"^[Ff][Ii][Ll][Ee]://?((/[=_0-9a-zA-Z%\\-]+(\\.[_0-9a-zA-Z]+)?)+(/|\\.[_0-9a-zA-Z]+)?)$"] evaluateWithObject:self];
    } else {
        return NO;
    }
}

- (NSString *)stringByDeletingScheme {
    NSRange range = [self rangeOfString:@"://"];
    if (range.location != NSNotFound) {
        return [self substringFromIndex:(range.location + range.length)];
    } else {
        return nil;
    }    
}

- (NSString *)stringDecorateWithUsername:(NSString *)username password:(NSString *)password {
//    if (!self.isValidateFTPURLString) {
//        return nil;
//    } else {
        BOOL usernameIsLegal = [[NSPredicate predicateWithFormat:@"SELF MATCHES %@", @"^\\w*$"] evaluateWithObject:username];
        BOOL passwordIsLegal = [[NSPredicate predicateWithFormat:@"SELF MATCHES %@", @"^[=_0-9a-zA-Z\\$\\(\\)\\*\\+\\-\\.\\[\\]\\?\\\\\\^\\{\\}\\|`~!#%&\'\",<>/]*$"] evaluateWithObject:password];

        if (usernameIsLegal && passwordIsLegal) {
            NSString *identityString = [NSString stringWithFormat:@"%@:%@@", username, password];

            int schemeEndPosition = 0;
            int hostBeginPosition = 0;

            for (int i = 0; i < self.length; i++) {
                if (i > 0 && [self characterAtIndex:i - 1] == (unichar)'/' && [self characterAtIndex:i] == (unichar)'/') {
                    schemeEndPosition = i;
                    hostBeginPosition = MIN(i + 1, (int)self.length - 1);
                    break;
                }
                if ([self characterAtIndex:i] == (unichar)'@') {
                    hostBeginPosition = MIN(i + 1, (int)self.length - 1);
                    break;
                }
            }

            return [NSString stringWithFormat:@"%@%@%@", [self substringToIndex:schemeEndPosition + 1], identityString, [self substringFromIndex:hostBeginPosition]];
        } else {
            return nil;
        }
//    }
}

@end

@interface LxFTPRequest () {
  @protected
    CFStreamClientContext _streamClientContext;
}
@property (nonatomic, assign) CFReadStreamRef readStream;
@property (nonatomic, assign) CFWriteStreamRef writeStream;
@property (nonatomic, assign) BOOL hasStopped;

@end

@implementation LxFTPRequest

- (void)dealloc {
    self.serverURL = nil;
    self.localFileURL = nil;
    self.username = nil;
    self.password = nil;
    self.finishedSize = 0;
    self.totalSize = 0;
    self.progressAction = nil;
    self.successAction = nil;
    self.failAction = nil;
}

- (instancetype)initPrivate {
    if (self = [super init]) {
        self.username = @"";
        self.password = @"";
        self.progressAction = ^(NSInteger totalSize, NSInteger finishedSize, CGFloat finishedPercent) {};
        self.successAction = ^(Class resultClass, id result) {};
        self.failAction = ^(CFStreamErrorDomain errorDomain, NSInteger error, NSString *errorDescription) {};

        _streamClientContext.version = 0;
        _streamClientContext.retain = 0;
        _streamClientContext.release = 0;
        _streamClientContext.copyDescription = 0;
        _streamClientContext.info = (void *)CFBridgingRetain(self);
    }
    return self;
}

- (void)setServerURL:(NSURL *)serverURL {
    if (_serverURL != serverURL) {
        _serverURL = serverURL;
    }
}

- (void)setLocalFileURL:(NSURL *)localFileURL {
    if (_localFileURL != localFileURL) {
        _localFileURL = localFileURL;
    }
}

- (BOOL)start {
    NSLog(@"LxFTPRequest: Need override by subclass!");
    return NO;
}

- (void)stop {
    CFBridgingRelease(_streamClientContext.info);
    _streamClientContext.info = NULL;
}

- (NSString *)errorMessageOfCode:(NSInteger)code {
    switch (code) {
        // Success codes
        case 150:
            return @"Đang chuẩn bị kết nối dữ liệu";
        case 200:
            return @"Lệnh thành công";
        case 226:
            return @"Hoàn tất thao tác";
        case 230:
            return @"Đăng nhập thành công";
        case 250:
            return @"Thao tác thành công";
        case 257:
            return @"Đã tạo thư mục";
            
        // Client error codes
        case 331:
            return @"Cần mật khẩu để đăng nhập";
        case 332:
            return @"Cần thông tin tài khoản";
        case 350:
            return @"Cần thêm thông tin";
        case 421:
            return @"Máy chủ không khả dụng, kết nối bị đóng";
        case 425:
            return @"Không thể mở kết nối dữ liệu";
        case 426:
            return @"Kết nối bị đóng, truyền dữ liệu bị hủy";
        case 450:
            return @"Không thể thực hiện thao tác";
        case 451:
            return @"Thao tác bị hủy do lỗi xử lý";
        case 452:
            return @"Không đủ không gian lưu trữ";
            
        // Server error codes
        case 500:
            return @"Lỗi cú pháp lệnh";
        case 501:
            return @"Lỗi tham số";
        case 502:
            return @"Lệnh không được hỗ trợ";
        case 503:
            return @"Thứ tự lệnh không đúng";
        case 504:
            return @"Tham số không được hỗ trợ";
        case 530:
            return @"Chưa đăng nhập";
        case 532:
            return @"Cần thông tin tài khoản để lưu trữ";
        case 550:
            return @"Thư mục hoặc tệp không tồn tại hoặc không có quyền truy cập";
        case 551:
            return @"Thao tác bị hủy, loại trang không xác định";
        case 552:
            return @"Thao tác bị hủy, vượt quá giới hạn lưu trữ";
        case 553:
            return @"Tên tệp không hợp lệ";
            
        default:
            return [NSString stringWithFormat:@"Lỗi FTP: %ld", (long)code];
    }
}

@end

@interface LxResourceListFTPRequest : LxFTPRequest

@property (nonatomic, strong) NSMutableData *listData;

@end

@implementation LxResourceListFTPRequest

- (instancetype)initPrivate {
    if (self = [super initPrivate]) {
        self.listData = [[NSMutableData alloc] init];
    }
    return self;
}

- (BOOL)start {
    if (self.serverURL == nil) {
        return NO;
    }

    self.readStream = CFReadStreamCreateWithFTPURL(kCFAllocatorDefault, (__bridge CFURLRef)self.serverURL);

    CFReadStreamSetProperty(self.readStream, kCFStreamPropertyFTPUserName, (__bridge CFTypeRef)self.username);
    CFReadStreamSetProperty(self.readStream, kCFStreamPropertyFTPPassword, (__bridge CFTypeRef)self.password);
    CFReadStreamSetProperty(self.readStream, kCFStreamPropertyFTPFetchResourceInfo, kCFBooleanTrue);
    CFReadStreamSetProperty(self.readStream, kCFStreamPropertyFTPAttemptPersistentConnection, kCFBooleanFalse);

    Boolean supportsAsynchronousNotification = CFReadStreamSetClient(
        self.readStream,
        kCFStreamEventNone |
            kCFStreamEventOpenCompleted |
            kCFStreamEventHasBytesAvailable |
            kCFStreamEventCanAcceptBytes |
            kCFStreamEventErrorOccurred |
            kCFStreamEventEndEncountered,
        resourceListReadStreamClientCallBack,
        &_streamClientContext);

    if (supportsAsynchronousNotification) {
    } else {
        return NO;
    }

    CFReadStreamScheduleWithRunLoop(self.readStream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);

    Boolean openStreamSuccess = CFReadStreamOpen(self.readStream);

    if (openStreamSuccess) {
        return YES;
    } else {
        return NO;
    }
}

void resourceListReadStreamClientCallBack(CFReadStreamRef stream, CFStreamEventType type, void *clientCallBackInfo) {
    LxResourceListFTPRequest *request = (__bridge LxResourceListFTPRequest *)clientCallBackInfo;

    switch (type) {
        case kCFStreamEventNone: {
        } break;
        case kCFStreamEventOpenCompleted: {
        } break;
        case kCFStreamEventHasBytesAvailable: {
            UInt8 buffer[RESOURCE_LIST_BUFFER_SIZE];
            CFIndex bytesRead = CFReadStreamRead(stream, buffer, RESOURCE_LIST_BUFFER_SIZE);

            if (bytesRead > 0) {
                [request.listData appendBytes:buffer length:bytesRead];
                request.progressAction(0, (NSInteger)request.listData.length, 0);
            } else if (bytesRead == 0) {
                NSMutableArray *resourceArray = [NSMutableArray array];

                CFIndex totalBytesParsed = 0;
                CFDictionaryRef parsedDictionary;

                do {
                    CFIndex bytesParsed = CFFTPCreateParsedResourceListing(kCFAllocatorDefault,
                                                                           &((const uint8_t *)request.listData.bytes)[totalBytesParsed],
                                                                           request.listData.length - totalBytesParsed,
                                                                           &parsedDictionary);
                    if (bytesParsed > 0) {
                        if (parsedDictionary != NULL) {
                            [resourceArray addObject:(__bridge id)parsedDictionary];
                            CFRelease(parsedDictionary);
                        }
                        totalBytesParsed += bytesParsed;
                        request.progressAction(0, (NSInteger)totalBytesParsed, 0);
                    } else if (bytesParsed == 0) {
                        break;
                    } else if (bytesParsed == -1) {
                        CFStreamError error = CFReadStreamGetError(stream);
                        request.failAction((CFStreamErrorDomain)error.domain, (NSInteger)error.error, [request errorMessageOfCode:error.error]);
                        [request stop];
                        return;
                    }
                } while (true);

                request.successAction([NSArray class], [NSArray arrayWithArray:resourceArray]);
                [request stop];
            } else {
                CFStreamError error = CFReadStreamGetError(stream);
                request.failAction((CFStreamErrorDomain)error.domain, (NSInteger)error.error, [request errorMessageOfCode:error.error]);
                [request stop];
            }

        } break;
        case kCFStreamEventCanAcceptBytes: {
        } break;
        case kCFStreamEventErrorOccurred: {
            CFStreamError error = CFReadStreamGetError(stream);
            request.failAction((CFStreamErrorDomain)error.domain, (NSInteger)error.error, [request errorMessageOfCode:error.error]);
            [request stop];
        } break;
        case kCFStreamEventEndEncountered: {
            [request stop];
        } break;
        default:
            break;
    }
}

- (void)stop {
    if (self.readStream == nil) return;

    [super stop];        
    CFReadStreamUnscheduleFromRunLoop(self.readStream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
    CFReadStreamClose(self.readStream);
    CFRelease(self.readStream);
    self.readStream = nil;
}

@end

@interface LxDownloadFTPRequest : LxFTPRequest
@end

@implementation LxDownloadFTPRequest

- (void)setLocalFileURL:(NSURL *)localFileURL {
    [super setLocalFileURL:localFileURL];

    NSString *localFilePath = self.localFileURL.absoluteString.stringByDeletingScheme;

    if (![[NSFileManager defaultManager] fileExistsAtPath:localFilePath]) {
        [[NSFileManager defaultManager] createFileAtPath:localFilePath contents:nil attributes:nil];
    }

    NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:localFilePath error:nil];
    self.finishedSize = [fileAttributes[NSFileSize] integerValue];
}

- (BOOL)start {
    self.hasStopped = false;
    if (self.localFileURL == nil) {
        return NO;
    }

    self.writeStream = CFWriteStreamCreateWithFile(kCFAllocatorDefault, (__bridge CFURLRef)self.localFileURL);
    CFWriteStreamSetProperty(self.writeStream, kCFStreamPropertyAppendToFile, kCFBooleanTrue);

    Boolean openWriteStreamSuccess = CFWriteStreamOpen(self.writeStream);

    if (openWriteStreamSuccess) {
    } else {
        return NO;
    }

    if (self.serverURL == nil) {
        return NO;
    }

    self.readStream = CFReadStreamCreateWithFTPURL(kCFAllocatorDefault, (__bridge CFURLRef)self.serverURL);

    CFReadStreamSetProperty(self.readStream, kCFStreamPropertyFTPUserName, (__bridge CFTypeRef)self.username);
    CFReadStreamSetProperty(self.readStream, kCFStreamPropertyFTPPassword, (__bridge CFTypeRef)self.password);
    CFReadStreamSetProperty(self.readStream, kCFStreamPropertyFTPFetchResourceInfo, kCFBooleanTrue);
    CFReadStreamSetProperty(self.readStream, kCFStreamPropertyFTPAttemptPersistentConnection, kCFBooleanFalse);
    CFReadStreamSetProperty(self.readStream, kCFStreamPropertyFTPFileTransferOffset, (__bridge CFTypeRef) @(self.finishedSize));

    Boolean supportsAsynchronousNotification = CFReadStreamSetClient(self.readStream,
                                                                     kCFStreamEventNone |
                                                                         kCFStreamEventOpenCompleted |
                                                                         kCFStreamEventHasBytesAvailable |
                                                                         kCFStreamEventCanAcceptBytes |
                                                                         kCFStreamEventErrorOccurred |
                                                                         kCFStreamEventEndEncountered,
                                                                     downloadReadStreamClientCallBack,
                                                                     &_streamClientContext);

    if (supportsAsynchronousNotification) {
        CFReadStreamScheduleWithRunLoop(self.readStream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
    } else {
        return NO;
    }

    Boolean openReadStreamSuccess = CFReadStreamOpen(self.readStream);

    if (openReadStreamSuccess) {
        return YES;
    } else {
        return NO;
    }
    
}

void downloadReadStreamClientCallBack(CFReadStreamRef stream, CFStreamEventType type, void *clientCallBackInfo) {
    LxDownloadFTPRequest *request = (__bridge LxDownloadFTPRequest *)clientCallBackInfo;

    switch (type) {
        case kCFStreamEventNone: {
        } break;
        case kCFStreamEventOpenCompleted: {
            CFNumberRef resourceSizeNumber = CFReadStreamCopyProperty(stream, kCFStreamPropertyFTPResourceSize);

            if (resourceSizeNumber) {
                long long resourceSize = 0;
                CFNumberGetValue(resourceSizeNumber, kCFNumberLongLongType, &resourceSize);
                request.totalSize = (NSInteger)resourceSize;

                CFRelease(resourceSizeNumber);
                resourceSizeNumber = nil;
            }

            if (request.finishedSize >= request.totalSize) {
                request.successAction([NSString class], request.localFileURL.absoluteString.stringByDeletingScheme);
                [request stop];
            }
        } break;
        case kCFStreamEventHasBytesAvailable: {
            UInt8 buffer[DOWNLOAD_BUFFER_SIZE];
            CFIndex bytesRead = CFReadStreamRead(stream, buffer, DOWNLOAD_BUFFER_SIZE);

            if (bytesRead > 0) {
                NSInteger bytesOffset = 0;
                do {
                    CFIndex bytesWritten = CFWriteStreamWrite(request.writeStream, &buffer[bytesOffset], bytesRead - bytesOffset);
                    if (bytesWritten > 0) {
                        bytesOffset += bytesWritten;
                        request.finishedSize += bytesWritten;
                        request.progressAction(request.totalSize, request.finishedSize, (CGFloat)request.finishedSize / (CGFloat)request.totalSize * 100);
                    } else if (bytesWritten == 0) {
                        break;
                    } else {
                        CFStreamError error = CFReadStreamGetError(stream);
                        request.failAction((CFStreamErrorDomain)error.domain, (NSInteger)error.error, [request errorMessageOfCode:error.error]);
                        [request stop];
                        return;
                    }

                } while (bytesRead - bytesOffset > 0);
            } else if (bytesRead == 0) {
                request.successAction([NSString class], request.localFileURL.absoluteString.stringByDeletingScheme);
                [request stop];
            } else {
                CFStreamError error = CFReadStreamGetError(stream);
                request.failAction((CFStreamErrorDomain)error.domain, (NSInteger)error.error, [request errorMessageOfCode:error.error]);
                [request stop];
            }
        } break;
        case kCFStreamEventCanAcceptBytes: {
        } break;
        case kCFStreamEventErrorOccurred: {
            CFStreamError error = CFReadStreamGetError(stream);
            request.failAction((CFStreamErrorDomain)error.domain, (NSInteger)error.error, [request errorMessageOfCode:error.error]);
            [request stop];
        } break;
        case kCFStreamEventEndEncountered: {
            request.successAction([NSString class], request.localFileURL.absoluteString.stringByDeletingScheme);
            [request stop];
        } break;
        default:
            break;
    }
}

- (void)stop {
    //Stop func has been called previously.
    //Putting this return statement here to prevent crash.
    if (self.hasStopped == true) return;
    
    CFReadStreamUnscheduleFromRunLoop(self.readStream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
    CFReadStreamClose(self.readStream);
    CFRelease(self.readStream);
    self.readStream = nil;

    CFWriteStreamClose(self.writeStream);
    CFRelease(self.writeStream);
    self.writeStream = nil;

    CFBridgingRelease(_streamClientContext.info);
    _streamClientContext.info = NULL;
    self.hasStopped = true;
}

@end

@interface LxUploadFTPRequest : LxFTPRequest

@end

@implementation LxUploadFTPRequest

- (void)setLocalFileURL:(NSURL *)localFileURL {
    [super setLocalFileURL:localFileURL];

    NSError *error = nil;

    NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:self.localFileURL.absoluteString.stringByRemovingPercentEncoding.stringByDeletingScheme error:&error];
    self.totalSize = [fileAttributes[NSFileSize] integerValue];
}

- (BOOL)start {
    if (self.localFileURL == nil) {
        return NO;
    }

    self.readStream = CFReadStreamCreateWithFile(kCFAllocatorDefault, (__bridge CFURLRef)self.localFileURL);

    Boolean openReadStreamSuccess = CFReadStreamOpen(self.readStream);

    if (openReadStreamSuccess) {
    } else {
        CFStreamError myErr = CFReadStreamGetError(self.readStream);
        self.failAction(myErr.domain,myErr.error,@"Open read stream failed");
        return NO;
    }

    if (self.serverURL == nil) {
        return NO;
    }

    self.writeStream = CFWriteStreamCreateWithFTPURL(kCFAllocatorDefault, (__bridge CFURLRef)self.serverURL);

    CFWriteStreamSetProperty(self.writeStream, kCFStreamPropertyFTPUserName, (__bridge CFTypeRef)self.username);
    CFWriteStreamSetProperty(self.writeStream, kCFStreamPropertyFTPPassword, (__bridge CFTypeRef)self.password);

    Boolean supportsAsynchronousNotification = CFWriteStreamSetClient(self.writeStream,
                                                                      kCFStreamEventNone |
                                                                          kCFStreamEventOpenCompleted |
                                                                          kCFStreamEventHasBytesAvailable |
                                                                          kCFStreamEventCanAcceptBytes |
                                                                          kCFStreamEventErrorOccurred |
                                                                          kCFStreamEventEndEncountered,
                                                                      uploadWriteStreamClientCallBack,
                                                                      &_streamClientContext);

    if (supportsAsynchronousNotification) {
        CFWriteStreamScheduleWithRunLoop(self.writeStream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
    } else {
        return NO;
    }

    Boolean openWriteStreamSuccess = CFWriteStreamOpen(self.writeStream);

    if (openWriteStreamSuccess) {
        return YES;
    } else {
        CFStreamError myErr = CFWriteStreamGetError(self.writeStream);
        self.failAction(myErr.domain,myErr.error,@"Open write stream failed");
        return NO;
    }
}

void uploadWriteStreamClientCallBack(CFWriteStreamRef stream, CFStreamEventType type, void *clientCallBackInfo) {
    LxUploadFTPRequest *request = (__bridge LxUploadFTPRequest *)clientCallBackInfo;

    switch (type) {
        case kCFStreamEventNone: {
        } break;
        case kCFStreamEventOpenCompleted: {
        } break;
        case kCFStreamEventHasBytesAvailable: {
        } break;
        case kCFStreamEventCanAcceptBytes: {
            UInt8 buffer[UPLOAD_BUFFER_SIZE];
            CFIndex bytesRead = CFReadStreamRead(request.readStream, buffer, UPLOAD_BUFFER_SIZE);

            if (bytesRead > 0) {
                NSInteger bytesOffset = 0;
                do {
                    CFIndex bytesWritten = CFWriteStreamWrite(request.writeStream, &buffer[bytesOffset], bytesRead - bytesOffset);
                    if (bytesWritten > 0) {
                        bytesOffset += bytesWritten;
                        request.finishedSize += bytesWritten;
                        request.progressAction(request.totalSize, request.finishedSize, (CGFloat)request.finishedSize / (CGFloat)request.totalSize * 100);
                    } else if (bytesWritten == 0) {
                        break;
                    } else {
                        CFStreamError error = CFWriteStreamGetError(stream);
                        request.failAction((CFStreamErrorDomain)error.domain, (NSInteger)error.error, [request errorMessageOfCode:error.error]);
                        [request stop];
                        return;
                    }
                } while (bytesRead - bytesOffset > 0);
            } else if (bytesRead == 0) {
                request.successAction([NSString class], request.serverURL.absoluteString);
                [request stop];
            } else {
                CFStreamError error = CFWriteStreamGetError(stream);
                request.failAction((CFStreamErrorDomain)error.domain, (NSInteger)error.error, [request errorMessageOfCode:error.error]);
                [request stop];
            }
        } break;
        case kCFStreamEventErrorOccurred: {
            CFStreamError error = CFWriteStreamGetError(stream);
            request.failAction((CFStreamErrorDomain)error.domain, (NSInteger)error.error, [request errorMessageOfCode:error.error]);
            [request stop];
        } break;
        case kCFStreamEventEndEncountered: {
            request.successAction([NSString class], request.serverURL.absoluteString);
            [request stop];
        } break;

        default:
            break;
    }
}

- (void)stop {
    [super stop];

    CFWriteStreamUnscheduleFromRunLoop(self.writeStream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
    CFWriteStreamClose(self.writeStream);
    CFRelease(self.writeStream);
    self.writeStream = nil;

    CFReadStreamClose(self.readStream);
    CFRelease(self.readStream);
    self.readStream = nil;
}

@end

@interface LxCreateResourceFTPRequest : LxFTPRequest

@end

@implementation LxCreateResourceFTPRequest

- (BOOL)start {
    if (self.serverURL == nil) {
        return NO;
    }

    self.writeStream = CFWriteStreamCreateWithFTPURL(kCFAllocatorDefault, (__bridge CFURLRef)self.serverURL);
    CFWriteStreamSetProperty(self.writeStream, kCFStreamPropertyFTPUserName, (__bridge CFTypeRef)self.username);
    CFWriteStreamSetProperty(self.writeStream, kCFStreamPropertyFTPPassword, (__bridge CFTypeRef)self.password);

    Boolean supportsAsynchronousNotification = CFWriteStreamSetClient(self.writeStream,
                                                                      kCFStreamEventNone |
                                                                          kCFStreamEventOpenCompleted |
                                                                          kCFStreamEventHasBytesAvailable |
                                                                          kCFStreamEventCanAcceptBytes |
                                                                          kCFStreamEventErrorOccurred |
                                                                          kCFStreamEventEndEncountered,
                                                                      createResourceWriteStreamClientCallBack,
                                                                      &_streamClientContext);

    if (supportsAsynchronousNotification) {
        CFWriteStreamScheduleWithRunLoop(self.writeStream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
    } else {
        return NO;
    }

    Boolean openWriteStreamSuccess = CFWriteStreamOpen(self.writeStream);

    if (openWriteStreamSuccess) {
        return YES;
    } else {
        return NO;
    }
}

void createResourceWriteStreamClientCallBack(CFWriteStreamRef stream, CFStreamEventType type, void *clientCallBackInfo) {
    LxCreateResourceFTPRequest *request = (__bridge LxCreateResourceFTPRequest *)clientCallBackInfo;

    switch (type) {
        case kCFStreamEventNone: {
        } break;
        case kCFStreamEventOpenCompleted: {
        } break;
        case kCFStreamEventHasBytesAvailable: {
        } break;
        case kCFStreamEventCanAcceptBytes: {
            request.successAction([NSString class], request.serverURL.absoluteString);
            [request stop];
        } break;
        case kCFStreamEventErrorOccurred: {
            CFStreamError error = CFWriteStreamGetError(stream);
            request.failAction((CFStreamErrorDomain)error.domain, (NSInteger)error.error, [request errorMessageOfCode:error.error]);
            [request stop];
        } break;
        case kCFStreamEventEndEncountered: {
            request.successAction([NSString class], request.serverURL.absoluteString);
            [request stop];
        } break;
        default:
            break;
    }
}

- (void)stop {
    [super stop];
    
    CFWriteStreamUnscheduleFromRunLoop(self.writeStream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
    CFWriteStreamClose(self.writeStream);
    CFRelease(self.writeStream);
    self.writeStream = nil;
}

@end

@interface LxDestoryResourceRequest : LxFTPRequest

@end

@implementation LxDestoryResourceRequest

- (BOOL)start {
    if (self.serverURL == nil) {
        return NO;
    }

    NSString *theWhileServerURLString = [self.serverURL.absoluteString stringDecorateWithUsername:self.username password:self.password];

    self.serverURL = [NSURL URLWithString:theWhileServerURLString];

    SInt32 errorCode = 0;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    Boolean destroyResourceSuccess = CFURLDestroyResource((__bridge CFURLRef)self.serverURL, &errorCode);
#pragma clang diagnostic pop

    if (destroyResourceSuccess) {
        self.successAction([NSString class], self.serverURL.absoluteString);
        return YES;
    } else {
        self.failAction(0, (NSInteger)errorCode, @"Unknown");
        return NO;
    }
}

- (void)stop {
    [super stop];
}

@end

@interface LxMakeDirectoryFTPRequest : LxFTPRequest
@end

@implementation LxMakeDirectoryFTPRequest

- (BOOL)start {
    if (self.serverURL == nil) {
        return NO;
    }

    // Set up the MKD command
    CFStringRef commandStr = CFSTR("MKD");
    
    // Use the full path instead of just the last path component
    NSString *directoryPath = self.serverURL.path;
    // Remove leading slash if it exists
    if ([directoryPath hasPrefix:@"/"]) {
        directoryPath = [directoryPath substringFromIndex:1];
    }
    // Remove trailing slash if it exists
    if ([directoryPath hasSuffix:@"/"]) {
        directoryPath = [directoryPath substringToIndex:directoryPath.length - 1];
    }
    
    CFStringRef argStr = (__bridge CFStringRef)directoryPath;
    
    // Create a write stream to the server (not to a specific file)
    self.writeStream = CFWriteStreamCreateWithFTPURL(kCFAllocatorDefault, (__bridge CFURLRef)self.serverURL);
    
    if (self.writeStream == nil) {
        return NO;
    }
    
    // Set authentication credentials
    CFWriteStreamSetProperty(self.writeStream, kCFStreamPropertyFTPUserName, (__bridge CFTypeRef)self.username);
    CFWriteStreamSetProperty(self.writeStream, kCFStreamPropertyFTPPassword, (__bridge CFTypeRef)self.password);
    
    // Create MKD command dictionary
    const void *keys[] = { kCFStreamPropertyFTPCommand, kCFStreamPropertyFTPCommandArgument };
    const void *values[] = { commandStr, argStr };
    
    CFDictionaryRef commandDict = CFDictionaryCreate(
        kCFAllocatorDefault,
        keys,
        values,
        2,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    
    // Set the command
    CFWriteStreamSetProperty(self.writeStream, kCFStreamPropertyFTPCustomCommands, commandDict);
    CFRelease(commandDict);
    
    // Set up asynchronous callbacks
    Boolean supportsAsynchronousNotification = CFWriteStreamSetClient(
        self.writeStream,
        kCFStreamEventNone |
            kCFStreamEventOpenCompleted |
            kCFStreamEventHasBytesAvailable |
            kCFStreamEventCanAcceptBytes |
            kCFStreamEventErrorOccurred |
            kCFStreamEventEndEncountered,
        makeDirectoryWriteStreamClientCallBack,
        &_streamClientContext);
    
    if (supportsAsynchronousNotification) {
        CFWriteStreamScheduleWithRunLoop(self.writeStream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
    } else {
        return NO;
    }
    
    // Open the stream to begin the operation
    Boolean openWriteStreamSuccess = CFWriteStreamOpen(self.writeStream);
    
    if (openWriteStreamSuccess) {
        return YES;
    } else {
        CFStreamError error = CFWriteStreamGetError(self.writeStream);
        NSLog(@"[FTP_ERROR] Failed to open write stream: domain=%ld, error=%ld", (long)error.domain, (long)error.error);
        return NO;
    }
}

void makeDirectoryWriteStreamClientCallBack(CFWriteStreamRef stream, CFStreamEventType type, void *clientCallBackInfo) {
    LxMakeDirectoryFTPRequest *request = (__bridge LxMakeDirectoryFTPRequest *)clientCallBackInfo;

    switch (type) {
        case kCFStreamEventNone: {
        } break;
        case kCFStreamEventOpenCompleted: {
        } break;
        case kCFStreamEventHasBytesAvailable: {
        } break;
        case kCFStreamEventCanAcceptBytes: {
            // Check for FTP status using available properties
            CFIndex statusCode = -1;
            
            // Try to get status code from CFStreamStatus
            CFStreamStatus streamStatus = CFWriteStreamGetStatus(stream);
            if (streamStatus == kCFStreamStatusError) {
                CFStreamError error = CFWriteStreamGetError(stream);
                NSLog(@"[FTP_ERROR] MKD failed with domain=%ld, error=%ld", (long)error.domain, (long)error.error);
                request.failAction((CFStreamErrorDomain)error.domain, (NSInteger)error.error, [request errorMessageOfCode:error.error]);
                [request stop];
                return;
            }
            
            // Assume success if no error at this point
            request.successAction([NSString class], request.serverURL.absoluteString);
            [request stop];
        } break;
        case kCFStreamEventErrorOccurred: {
            CFStreamError error = CFWriteStreamGetError(stream);
            NSLog(@"[FTP_ERROR] MKD failed with domain=%ld, error=%ld", (long)error.domain, (long)error.error);
            request.failAction((CFStreamErrorDomain)error.domain, (NSInteger)error.error, [request errorMessageOfCode:error.error]);
            [request stop];
        } break;
        case kCFStreamEventEndEncountered: {
            // Since we can't reliably get the status code directly,
            // assume success if we've reached the end of the stream without errors
            CFStreamStatus streamStatus = CFWriteStreamGetStatus(stream);
            if (streamStatus == kCFStreamStatusError) {
                CFStreamError error = CFWriteStreamGetError(stream);
                request.failAction((CFStreamErrorDomain)error.domain, (NSInteger)error.error, [request errorMessageOfCode:error.error]);
            } else {
                request.successAction([NSString class], request.serverURL.absoluteString);
            }
            [request stop];
        } break;
        default:
            break;
    }
}

- (void)stop {
    [super stop];
    
    CFWriteStreamUnscheduleFromRunLoop(self.writeStream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
    CFWriteStreamClose(self.writeStream);
    CFRelease(self.writeStream);
    self.writeStream = nil;
}

@end

@implementation LxRenameFTPRequest

- (BOOL)start {
    if (self.serverURL == nil || self.destinationURL == nil) {
        NSLog(@"[FTPREQ_ERROR] Missing source or destination URL in rename operation");
        return NO;
    }

    // Create a write stream for the operation
    self.writeStream = CFWriteStreamCreateWithFTPURL(kCFAllocatorDefault, (__bridge CFURLRef)self.serverURL);
    if (self.writeStream == NULL) {
        NSLog(@"[FTPREQ_ERROR] Failed to create write stream with URL: %@", self.serverURL);
        return NO;
    }
    
    // Set authentication credentials
    CFWriteStreamSetProperty(self.writeStream, kCFStreamPropertyFTPUserName, (__bridge CFTypeRef)self.username);
    CFWriteStreamSetProperty(self.writeStream, kCFStreamPropertyFTPPassword, (__bridge CFTypeRef)self.password);
    
    // Get the source path without leading slash for RNFR command
    NSString *sourcePath = self.serverURL.path;
    if ([sourcePath hasPrefix:@"/"]) {
        sourcePath = [sourcePath substringFromIndex:1]; // Remove leading slash
    }
    
    // Get the destination path without leading slash for RNTO command
    NSString *destinationPath = self.destinationURL.path;
    if ([destinationPath hasPrefix:@"/"]) {
        destinationPath = [destinationPath substringFromIndex:1]; // Remove leading slash
    }
    
    NSLog(@"[FTPREQ_DEBUG] Rename operation: %@ → %@", sourcePath, destinationPath);
    
    // Create RNFR command
    const void *rnfrKeys[] = { kCFStreamPropertyFTPCommand, kCFStreamPropertyFTPCommandArgument };
    const void *rnfrValues[] = { CFSTR("RNFR"), (__bridge CFStringRef)sourcePath };
    
    CFDictionaryRef rnfrDictionary = CFDictionaryCreate(
        kCFAllocatorDefault,
        rnfrKeys,
        rnfrValues,
        2,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    
    // Create RNTO command
    const void *rntoKeys[] = { kCFStreamPropertyFTPCommand, kCFStreamPropertyFTPCommandArgument };
    const void *rntoValues[] = { CFSTR("RNTO"), (__bridge CFStringRef)destinationPath };
    
    CFDictionaryRef rntoDictionary = CFDictionaryCreate(
        kCFAllocatorDefault,
        rntoKeys,
        rntoValues,
        2,
        &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);
    
    // Create the command sequence array
    CFMutableArrayRef commandsArray = CFArrayCreateMutable(
        kCFAllocatorDefault,
        2,
        &kCFTypeArrayCallBacks);
    
    CFArrayAppendValue(commandsArray, rnfrDictionary);
    CFArrayAppendValue(commandsArray, rntoDictionary);
    
    // Set the command sequence property
    CFWriteStreamSetProperty(self.writeStream, kCFStreamPropertyFTPCommandAppendSequence, commandsArray);
    
    // Clean up CF objects
    CFRelease(rnfrDictionary);
    CFRelease(rntoDictionary);
    CFRelease(commandsArray);
    
    // Disable persistent connection to ensure clean handling of the commands
    CFWriteStreamSetProperty(self.writeStream, kCFStreamPropertyFTPAttemptPersistentConnection, kCFBooleanFalse);
    
    // Set up asynchronous client callbacks
    Boolean supportsAsynchronousNotification = CFWriteStreamSetClient(
        self.writeStream,
        kCFStreamEventNone |
            kCFStreamEventOpenCompleted |
            kCFStreamEventHasBytesAvailable |
            kCFStreamEventCanAcceptBytes |
            kCFStreamEventErrorOccurred |
            kCFStreamEventEndEncountered,
        renameWriteStreamClientCallBack,
        &_streamClientContext);
    
    if (!supportsAsynchronousNotification) {
        NSLog(@"[FTPREQ_ERROR] Stream does not support asynchronous notification");
        return NO;
    }
    
    // Schedule with run loop
    CFWriteStreamScheduleWithRunLoop(self.writeStream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
    
    // Open the stream to start the operation
    Boolean openSuccess = CFWriteStreamOpen(self.writeStream);
    if (!openSuccess) {
        CFStreamError error = CFWriteStreamGetError(self.writeStream);
        NSLog(@"[FTPREQ_ERROR] Failed to open stream: domain=%ld, error=%ld", (long)error.domain, (long)error.error);
        return NO;
    }
    
    NSLog(@"[FTPREQ_DEBUG] Rename operation started successfully");
    return YES;
}

void renameWriteStreamClientCallBack(CFWriteStreamRef stream, CFStreamEventType type, void *clientCallBackInfo) {
    LxRenameFTPRequest *request = (__bridge LxRenameFTPRequest *)clientCallBackInfo;
    
    switch (type) {
        case kCFStreamEventNone:
            break;
            
        case kCFStreamEventOpenCompleted:
            NSLog(@"[FTPREQ_DEBUG] Stream opened successfully");
            break;
            
        case kCFStreamEventHasBytesAvailable:
            // This shouldn't happen for a write stream
            NSLog(@"[FTPREQ_DEBUG] Stream has bytes available (unexpected for write stream)");
            break;
            
        case kCFStreamEventCanAcceptBytes: {
            // This event indicates the server is ready to accept bytes or the command has been processed
          CFTypeRef statusCode = CFWriteStreamCopyProperty(stream, kCFStreamPropertyFTPPassword);
            if (statusCode) {
                NSInteger code = [(__bridge NSNumber *)statusCode integerValue];
                NSLog(@"[FTPREQ_DEBUG] FTP status code: %ld", (long)code);
                CFRelease(statusCode);
                
                // 250 represents successful command completion for both RNFR and RNTO
                if (code == 250) {
                    NSLog(@"[FTPREQ_DEBUG] Rename operation successful");
                    request.successAction([NSString class], request.destinationURL.absoluteString);
                    [request stop];
                }
            }
            break;
        }
            
        case kCFStreamEventErrorOccurred: {
            CFStreamError error = CFWriteStreamGetError(stream);
            NSLog(@"[FTPREQ_ERROR] Stream error: domain=%ld, error=%ld", (long)error.domain, (long)error.error);
            request.failAction((CFStreamErrorDomain)error.domain, (NSInteger)error.error, [request errorMessageOfCode:error.error]);
            [request stop];
            break;
        }
            
        case kCFStreamEventEndEncountered: {
            // The stream has ended, check if we need to report success
          CFTypeRef statusCode = CFWriteStreamCopyProperty(stream, kCFStreamPropertyFTPPassword);
            if (statusCode) {
                NSInteger code = [(__bridge NSNumber *)statusCode integerValue];
                CFRelease(statusCode);
                
                // Check for success status code (250 for successful completion)
                if (code == 250) {
                    NSLog(@"[FTPREQ_DEBUG] Rename operation completed successfully");
                    request.successAction([NSString class], request.destinationURL.absoluteString);
                } else {
                    NSLog(@"[FTPREQ_ERROR] Rename operation failed with status code: %ld", (long)code);
                    request.failAction(kCFStreamErrorDomainCustom, code, [request errorMessageOfCode:code]);
                }
            } else {
                // No status code available, assume success if we reached end without errors
                NSLog(@"[FTPREQ_DEBUG] Stream ended without explicit status code, assuming success");
                request.successAction([NSString class], request.destinationURL.absoluteString);
            }
            
            [request stop];
            break;
        }
            
        default:
            NSLog(@"[FTPREQ_DEBUG] Unknown stream event: %ld", (long)type);
            break;
    }
}

- (void)stop {
    NSLog(@"[FTPREQ_DEBUG] Stopping rename request");
    [super stop];
    
    if (self.writeStream != NULL) {
        CFWriteStreamUnscheduleFromRunLoop(self.writeStream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
        CFWriteStreamClose(self.writeStream);
        CFRelease(self.writeStream);
        self.writeStream = nil;
    }
}

@end

@implementation LxFTPRequest (Create)

+ (LxFTPRequest *)resourceListRequest {
    return [[LxResourceListFTPRequest alloc] initPrivate];
}

+ (LxFTPRequest *)downloadRequest {
    return [[LxDownloadFTPRequest alloc] initPrivate];
}

+ (LxFTPRequest *)uploadRequest {
    return [[LxUploadFTPRequest alloc] initPrivate];
}

+ (LxFTPRequest *)createResourceRequest {
    return [[LxCreateResourceFTPRequest alloc] initPrivate];
}

+ (LxFTPRequest *)destoryResourceRequest {
    return [[LxDestoryResourceRequest alloc] initPrivate];
}

+ (LxFTPRequest *)makeDirectoryRequest {
    return [[LxMakeDirectoryFTPRequest alloc] initPrivate];
}

+ (LxFTPRequest *)renameRequest {
    return [[LxRenameFTPRequest alloc] initPrivate];
}

@end
