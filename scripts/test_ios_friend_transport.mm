// SPDX-License-Identifier: GPL-3.0-or-later
#include "platform/iosfriendtransport.h"
#include <QCoreApplication>
#include <QElapsedTimer>
#include <QThread>
#include <atomic>
#include <cassert>
#include <cstdio>
#import <Foundation/Foundation.h>

static std::atomic<int> mode{0}, starts{0};
@interface FKFriendTestProtocol : NSURLProtocol
@property BOOL stopped;
@end
@implementation FKFriendTestProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
  ++starts;
  assert([[self.request valueForHTTPHeaderField:@"User-Agent"] isEqualToString:@"Xinyuesha-Test/0.5.25"]);
  assert(!self.request.HTTPShouldHandleCookies);
  if ([self.request.HTTPMethod isEqualToString:@"POST"]) {
    NSMutableData *body = [NSMutableData dataWithData:self.request.HTTPBody ?: [NSData data]];
    if (!body.length && self.request.HTTPBodyStream) {
      NSInputStream *stream = self.request.HTTPBodyStream; [stream open];
      uint8_t buffer[1024]; NSInteger count;
      while ((count = [stream read:buffer maxLength:sizeof buffer]) > 0) [body appendBytes:buffer length:count];
      [stream close];
    }
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
    assert([json[@"name"] isEqualToString:@"测试"]);
    assert([[self.request valueForHTTPHeaderField:@"Authorization"] isEqualToString:@"Bearer fixture-token"]);
  }
  const int current = mode.load();
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 50 * NSEC_PER_MSEC), dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
    @synchronized(self) {
      if (self.stopped) return;
      if (current) {
        const NSInteger code = current == 1 ? NSURLErrorNotConnectedToInternet : NSURLErrorTimedOut;
        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:code userInfo:nil]];
      } else {
        NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:401 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/json; charset=utf-8"}];
        [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
        [self.client URLProtocol:self didLoadData:[@"{\"error\":\"好友服务登录已失效\"}" dataUsingEncoding:NSUTF8StringEncoding]];
        [self.client URLProtocolDidFinishLoading:self];
      }
    }
  });
}
- (void)stopLoading { @synchronized(self) { self.stopped = YES; } }
@end

static void pump(int ms) {
  QElapsedTimer timer;timer.start();
  while (timer.elapsed() < ms) {
    QCoreApplication::processEvents();
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.001]];
    QThread::msleep(1);
  }
}
static void until(const std::function<bool()> &ready) {
  QElapsedTimer timer;timer.start();
  while (!ready() && timer.elapsed() < 3000) pump(5);
  assert(ready());
}
int main(int argc, char **argv) {
  QCoreApplication app(argc, argv);
  @autoreleasepool {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    config.protocolClasses = @[[FKFriendTestProtocol class]];
    IosFriendTransport transport(nullptr, (__bridge void *)config);
    int callbacks = 0, status = -1, code = 0;QString body, failure;
    auto completed = [&](qint64, int s, const QString &b, int c, const QString &f) {
      assert(QThread::currentThread() == app.thread());++callbacks;status=s;body=b;code=c;failure=f;
    };
    const QString url = QStringLiteral("https://freekill-friends.pages.dev/v1/accounts/login");
    transport.send(1, QStringLiteral("POST"), url, QStringLiteral("fixture-token"), QStringLiteral("{\"name\":\"测试\"}"), completed);
    until([&]{return callbacks==1;});
    assert(status==401 && code==0 && body.contains(QStringLiteral("好友服务登录已失效")));
    mode=1;transport.send(2,QStringLiteral("GET"),url,{}, {}, completed);until([&]{return callbacks==2;});
    assert(status==0 && code==-1009 && failure.contains(QStringLiteral("NSURLErrorDomain")));
    mode=2;transport.send(3,QStringLiteral("GET"),url,{}, {}, completed);until([&]{return callbacks==3;});
    assert(status==0 && code==-1001 && failure.contains(QStringLiteral("超时")));
    mode=0;transport.send(4,QStringLiteral("GET"),url,{}, {}, completed);transport.cancel(4);pump(200);assert(callbacks==3);
    auto *destroyed = new IosFriendTransport(nullptr, (__bridge void *)config);
    destroyed->send(5,QStringLiteral("GET"),url,{}, {}, completed);delete destroyed;pump(200);assert(callbacks==3);
    const int previous = starts.load();
    transport.send(6,QStringLiteral("POST"),QStringLiteral("https://example.com/v1/state"),{}, {}, completed);
    until([&]{return callbacks==4;});assert(code==-1 && starts==previous);
    transport.send(7,QStringLiteral("PATCH"),url,{}, {}, completed);transport.cancel(7);pump(50);assert(callbacks==4);
    puts("Native NSURLSession: UTF-8 POST/auth/status, main-thread completion, network codes, cancellation, destruction and origin policy passed.");
  }
}
