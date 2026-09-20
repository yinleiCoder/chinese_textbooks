import 'dart:async';

import 'package:chinese_textbooks/entity/entity.dart';
import 'package:chinese_textbooks/services/download/download.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RequestGate 并发上限', () {
    test('放行数不超过上限，释放后继续放行', () async {
      final RequestGate gate = RequestGate(
        maxConcurrent: 2,
        minInterval: Duration.zero,
      );

      await gate.acquire();
      await gate.acquire();
      expect(gate.runningCount, 2);

      bool third = false;
      unawaited(gate.acquire().then((_) => third = true));
      await Future<void>.delayed(Duration.zero);
      expect(third, isFalse, reason: '达到上限后第三个应当等待');

      gate.release();
      await Future<void>.delayed(Duration.zero);
      expect(third, isTrue, reason: '释放一个槽位后应当唤醒等待者');
    });
  });

  group('RequestGate 最小间隔', () {
    test('相邻放行之间至少间隔设定时长', () async {
      final RequestGate gate = RequestGate(
        maxConcurrent: 1,
        minInterval: const Duration(milliseconds: 120),
      );

      final Stopwatch watch = Stopwatch()..start();
      await gate.acquire();
      gate.release();
      await gate.acquire();
      watch.stop();

      // 这里的"发起时刻"是 acquire 返回的时刻，两次之间必须被拉开。
      expect(
        watch.elapsedMilliseconds,
        greaterThanOrEqualTo(100),
        reason: '间隔约束不能形同虚设',
      );
    });
  });

  group('MirrorPlanner', () {
    const MirrorPlanner planner = MirrorPlanner();
    final DownloadTask task = DownloadTask(
      textbookId: 'book-1',
      title: '语文一年级上册',
      mirrors: <Uri>[
        Uri.parse('https://r1-ndr-private.ykt.cbern.com.cn/a/b.pdf'),
        Uri.parse('https://r2-ndr-private.ykt.cbern.com.cn/a/b.pdf'),
        Uri.parse('https://r3-ndr-private.ykt.cbern.com.cn/a/b.pdf'),
      ],
      expectedBytes: 100,
    );

    test('已登录时直接走私有域，不浪费一次公开域请求', () {
      final List<Uri> plan = planner.plan(task, loggedIn: true);
      expect(plan, hasLength(3));
      expect(plan.every((Uri u) => u.host.contains('-private.')), isTrue);
      expect(plan.first.host, 'r1-ndr-private.ykt.cbern.com.cn');
    });

    test('未登录时先试公开镜像，再回落到私有域', () {
      final List<Uri> plan = planner.plan(task, loggedIn: false);
      expect(plan, hasLength(6));
      expect(plan.take(3).every((Uri u) => !u.host.contains('-private.')), isTrue);
      expect(plan.skip(3).every((Uri u) => u.host.contains('-private.')), isTrue);
    });

    test('已确认需要签名时不再白撞公开域', () {
      final List<Uri> plan = planner.plan(
        task.withRequiresAuth(),
        loggedIn: false,
      );
      expect(plan, hasLength(3));
      expect(plan.every((Uri u) => u.host.contains('-private.')), isTrue);
    });

    test('没有镜像时返回空序列', () {
      const DownloadTask empty = DownloadTask(
        textbookId: 'x',
        title: 'x',
        mirrors: <Uri>[],
        expectedBytes: 0,
      );
      expect(planner.plan(empty, loggedIn: true), isEmpty);
    });
  });
}
