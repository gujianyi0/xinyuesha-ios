// SPDX-License-Identifier: GPL-3.0-or-later
#include "platform/iosfriendtransport.h"
#include <QHash>
#include <QPointer>
#include <QTimer>
#include <QUrl>
#import <Foundation/Foundation.h>
#import <dispatch/dispatch.h>

@interface FKFriendSessionDelegate : NSObject <NSURLSessionTaskDelegate>
@end
@implementation FKFriendSessionDelegate
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    willPerformHTTPRedirection:(NSHTTPURLResponse *)response
    newRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSURLRequest *))completionHandler {
  // The published API does not redirect. Never forward an account credential
  // to a redirect target; report the original 3xx response to the caller.
  completionHandler(nil);
}
@end

struct IosFriendTransport::Impl {
  struct Pending { __strong NSURLSessionDataTask *task; Completion completed; };
  __strong NSURLSession *session;
  QHash<qint64, Pending> pending;
};

static QString networkFailure(NSError *error) {
  if (!error) return {};
  QString detail;
  if ([error.domain isEqualToString:NSURLErrorDomain]) {
    switch (error.code) {
    case NSURLErrorTimedOut: detail = QStringLiteral("请求超时"); break;
    case NSURLErrorCannotFindHost: detail = QStringLiteral("域名解析失败"); break;
    case NSURLErrorCannotConnectToHost: detail = QStringLiteral("无法建立连接"); break;
    case NSURLErrorNetworkConnectionLost: detail = QStringLiteral("连接中断"); break;
    case NSURLErrorNotConnectedToInternet: detail = QStringLiteral("应用当前没有可用网络"); break;
    case NSURLErrorDataNotAllowed: detail = QStringLiteral("当前网络不允许传输数据"); break;
    case NSURLErrorSecureConnectionFailed: detail = QStringLiteral("TLS 连接失败"); break;
    case NSURLErrorServerCertificateUntrusted: detail = QStringLiteral("服务器证书不受信任"); break;
    case NSURLErrorAppTransportSecurityRequiresSecureConnection: detail = QStringLiteral("系统连接安全策略拒绝请求"); break;
    default: detail = QStringLiteral("系统网络请求失败"); break;
    }
  } else detail = QStringLiteral("系统网络请求失败");
  // No headers, body, userInfo or credential-bearing URL is exposed.
  return QStringLiteral("%1（%2 / %3）").arg(detail, QString::fromNSString(error.domain)).arg(error.code);
}

IosFriendTransport::IosFriendTransport(QObject *parent, void *configuration)
    : QObject(parent), impl(std::make_unique<Impl>()) {
  @autoreleasepool {
    NSURLSessionConfiguration *config = configuration
        ? [(__bridge NSURLSessionConfiguration *)configuration copy]
        : [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.timeoutIntervalForRequest = 12;
    config.timeoutIntervalForResource = 15;
    config.waitsForConnectivity = NO;
    config.allowsCellularAccess = YES;
    config.allowsExpensiveNetworkAccess = YES;
    config.allowsConstrainedNetworkAccess = YES;
    config.HTTPCookieStorage = nil;
    config.HTTPShouldSetCookies = NO;
    config.URLCache = nil;
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    impl->session = [NSURLSession sessionWithConfiguration:config
        delegate:[FKFriendSessionDelegate new] delegateQueue:nil];
  }
}

IosFriendTransport::~IosFriendTransport() {
  [impl->session invalidateAndCancel];
  impl->pending.clear();
}

void IosFriendTransport::send(qint64 id, const QString &method, const QString &url,
    const QString &bearer, const QString &body, Completion completed) {
  const QUrl target(url, QUrl::StrictMode);
  const bool origin = target.scheme() == QStringLiteral("https") &&
      (target.host() == QStringLiteral("freekill-friends.pages.dev") ||
       target.host() == QStringLiteral("xinyuesha-friends-api.pages.dev")) &&
      target.port(443) == 443 && target.userInfo().isEmpty() &&
      !target.hasQuery() && !target.hasFragment();
  const bool valid = target.isValid() && origin &&
      target.path().startsWith(QStringLiteral("/v1/")) &&
      (method == QStringLiteral("GET") || method == QStringLiteral("POST")) &&
      body.toUtf8().size() <= 65536 && !bearer.contains('\r') && !bearer.contains('\n');
  if (!valid) {
    impl->pending.insert(id, {nil, std::move(completed)});
    QTimer::singleShot(0, this, [this, id]() {
      auto it = impl->pending.find(id);
      if (it == impl->pending.end()) return;
      const auto callback = std::move(it->completed);
      impl->pending.erase(it);
      callback(id, 0, {}, -1, QStringLiteral("好友请求地址或参数不受支持"));
    });
    return;
  }
  @autoreleasepool {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:
        [NSURL URLWithString:url.toNSString()]];
    request.HTTPMethod = method.toNSString();
    request.HTTPShouldHandleCookies = NO;
    [request setValue:@"Xinyuesha-Test/0.5.25" forHTTPHeaderField:@"User-Agent"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    if (!bearer.isEmpty()) [request setValue:(QStringLiteral("Bearer ") + bearer).toNSString()
        forHTTPHeaderField:@"Authorization"];
    if (method == QStringLiteral("POST")) {
      [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
      const QByteArray utf8 = body.toUtf8();
      request.HTTPBody = [NSData dataWithBytes:utf8.constData() length:utf8.size()];
    }
    const QPointer<IosFriendTransport> guard(this);
    NSURLSessionDataTask *task = [impl->session dataTaskWithRequest:request
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      const int status = [response isKindOfClass:[NSHTTPURLResponse class]]
          ? int(((NSHTTPURLResponse *)response).statusCode) : 0;
      const bool tooLarge = data.length > 2 * 1024 * 1024;
      const QString text = tooLarge ? QString() : QString::fromUtf8(
          static_cast<const char *>(data.bytes), qsizetype(data.length));
      const int code = tooLarge ? -2 : error ? int(error.code) : 0;
      const QString failure = tooLarge ? QStringLiteral("好友服务响应过大") : networkFailure(error);
      // Qt objects and QML callbacks are touched only on the Apple main queue.
      dispatch_async(dispatch_get_main_queue(), ^{
        if (!guard) return;
        auto it = guard->impl->pending.find(id);
        if (it == guard->impl->pending.end()) return; // cancelled/logged out
        const auto callback = std::move(it->completed);
        guard->impl->pending.erase(it);
        callback(id, tooLarge || error ? 0 : status, text, code, failure);
      });
    }];
    impl->pending.insert(id, {task, std::move(completed)});
    [task resume];
  }
}

void IosFriendTransport::cancel(qint64 id) {
  auto it = impl->pending.find(id);
  if (it == impl->pending.end()) return;
  [it->task cancel];
  impl->pending.erase(it);
}
