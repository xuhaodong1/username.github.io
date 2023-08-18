---
title: "iOS中的内存管理｜循环引用的监测(MLeaksFinder&FBRetainCycleDector)"
date: 2023-08-18 09:49:00
categories:
  - iOS
tags:
  - 内存管理
---

## 有哪些方式可以监测循环引用？

在引用计数的内存管理方式中，由于对象间的引用，最后引用关系图形成“环”才导致循环引用。因此对循环引用的监测直观的想法只需要找到这个环就可以找到循环引用的地方，也就是在有向图中找环（也可以说在树中找环），同时需要找到环中具体的节点，例如 FBRetainCycleDector 就是采用 DFS 进行图中环的检测与查找。
<!-- more -->
不过还有另一种方式，就是假定对象会很快释放。例如当一个 `vc` 被 `pop` 或 `dismiss` 之后，应该认为该 `vc` 包括它上面的子 `vc`，以及它的 `view`，`view` 的 `subView` 等，都会被很快释放，如果某个对象没有被释放，就认为该对象内存泄漏了,例如 MLeaksFinder 它的基本原理就是这样。

从实际场景分析，监测可以从两个方向着手：静态分析和动态分析。静态分析通过将源代码转换成抽象语法树（AST、Abstract Syntax Tree），从而检测出所有违反规则的代码信息，常见的分析工具有 Clang Static Analyzer、Infer、OCLint 与 SwiftLint；动态分析则是在应用运行起来后，分析其中的内存分配信息，常见的分析工具有 Instrument-Leaks、Memory Graph、MLeaksFinder、FBRetainCycleDector、OOMDetector 等。

由于开源和典型，就从 MLeaksFinder、FBRetainCycleDector 的源代码入手，看看他们的具体实现方案：

## MLeaksFinder

MLeaksFinder 的核心逻辑比较简单：

它利用 Method Swizzle HOOK 了许多 UIKit 相关类，如 `UIViewController`、`UIView`、`UINavigationController`、`UIPageViewController` 等，并拓展了 `NSObject`，为其添加 `willDealloc` 方法。在 `UIViewController` 或者 `UINavigationController` 在调用 `dismiss`、`pop` 时，就会调用 `vc`、`vc` 的子 `viewControllers`、`vc` 的 `view`、`view` 的 `subView` 的 `willDealloc` 方法。利用 `weak` 与 GCD，在两秒后查看对象是否存在。如果存在就会开启一个弹窗，根据宏定义选择输出利用 `FBRetainCycleDetector` 查找出来的循环引用链。

但这样的内存方式存在两种方式的“误判”：

* 单例或者被缓存起来的 `view` 或 `vc`
* 释放不及时的 `view` 或者 `vc`

对此，MLeaksFinder 也进行了一系列的措施进行补救：

* 通过 assert 保证调用在主线程，按 `vc`、`vc` 的子 `viewcontrollers`、`vc` 的 `view` 这样的顺序调用它们的 `willDealloc`，并其向主线程追加是否存在对象（`willDealloc`）的任务。因为主线程是串行队列，因此 GCD 的回调总也是按顺序调用的。

* 利用关联对象 `parentPtrs`，在上述顺序调用的过程中将 `vc` 或者 `view` 的所有未被释放的父级对象存储。
* 同时引入了静态对象 `leakedObjectPtrs`，将最优先回调的对象（最上层的对象）加入到 `leakedObjectPtrs` 中，如果子对象和 `leakedObjectPtrs` 有相同的交集，就不会弹窗，直接退出，这也保证了在同一个层级树中只有一个弹窗的调用。如果对象被销毁（可能是释放不及时的 `vc` 或者 `view`）了，则将其地址从 `leakedObjectPtrs` 移除。

单例或者被缓存起来的 `view` 或 `vc` 来说，由于 `leakedObjectPtrs` 留有一份地址，所以当重复进入、退出页面时，不会重复进行弹窗；

对于释放不及时的 `view` 或者 `vc` 来说，在未被释放前，会产生弹窗，在释放之后，弹出的信息变为 `Object Deallocated`，也就是不仅会重复弹窗，而且还有新加弹窗。这是因为对于 `vc` 和 `view` 来说，它们的内存往往占用较大，因此应该立即被释放，如网络回调中 `block` 的强持有，这种情况就应把强引用改为弱引用；

对于真正循环引用的对象，由于每次都会创建新的对象，因此会重复弹窗；

不过 MLeaksFinder 的缺点也很明显，大部分只能用来对它做 `view`、`vc` 的循环引用监测，对于 C/C++ 的内存泄漏，以及自定义对象维护成本较高，算是一个轻量级的方案。

```objc
- (BOOL)willDealloc {
    NSString *className = NSStringFromClass([self class]);
    if ([[NSObject classNamesWhitelist] containsObject:className])
        return NO;
    
    __weak id weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        __strong id strongSelf = weakSelf;
        [strongSelf assertNotDealloc];
    });
    
    return YES;
}
```

## FBRetainCycleDector

### 基本使用

提供一个对象，`FBRetainCycleDector` 就能以这个对象作为起始节点查找循环引用链，同时还可以根据需求传入 `configuration` 配置项，包含是否监测 `timer`、是否包含 `block` 地址以及自定义过滤强引用链等内容。在 `MLeaksFinder` 是这样使用的：

```objc
#if _INTERNAL_MLF_RC_ENABLED
FBRetainCycleDetector *detector = [FBRetainCycleDetector new];
[detector addCandidate:self.object];
NSSet *retainCycles = [detector findRetainCyclesWithMaxCycleLength:20];

BOOL hasFound = NO;
for (NSArray *retainCycle in retainCycles) {
    NSInteger index = 0;
    for (FBObjectiveCGraphElement *element in retainCycle) {
        // 查找特定的循环引用链
        if (element.object == object) {
            NSArray *shiftedRetainCycle = [self shiftArray:retainCycle toIndex:index];

            dispatch_async(dispatch_get_main_queue(), ^{
                [MLeaksMessenger alertWithTitle:@"Retain Cycle"
                                        message:[NSString stringWithFormat:@"%@", shiftedRetainCycle]];
            });
            hasFound = YES;
            break;
        }

        ++index;
    }
    if (hasFound) {
        break;
    }
}
if (!hasFound) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [MLeaksMessenger alertWithTitle:@"Retain Cycle"
                                message:@"Fail to find a retain cycle"];
    });
}
#endif
```

对于关联对象，由于其在对象的内存布局中不存在，`FBRetainCycleDector` 采用 `fishhook` 追踪了 `objc_setAssociatedObject` 和 `objc_resetAssociatedObjects` 方法，使得关于关联对象的循环引用得以捕获。但需要尽早进行 `hook`，例如在 `main.m` 中：

```objc
#import <FBRetainCycleDetector/FBAssociationManager.h>

int main(int argc, char * argv[]) {
  @autoreleasepool {
    [FBAssociationManager hook];
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
  }
}
```

### 总览

FBRetainCycleDetector 围绕着 `FBRetainCycleDetector` 类展开，通过初始化传入 `configuration` 以及后续添加待监测对象 `addCandidate`，这时整个对象便以构建完成。最后执行 `findRetainCycles` 方法进行循环引用查找并返回循环引用链。它的核心类图如下：

![image-20230814165245228](/images/blog/image-20230814165245228.png)

传入的对象会被封装为 `FBObjectiveCGraphElement` 类型，同时它有三个子类 `FBObjectiveCBlock`、`FBObjectiveCObject` 与 `FBObjectiveCNSCFTimer`。这是因为需要弱引用待检测对象，同时不同对象的内存布局不同（如分为普通 `NSObject` 对象，`block` 对象，`timer` 对象），不仅如此封装还可以加入更多的对象细节以便开发者排查。

### 算法分析

查找循环引用的算法逻辑主要集中在 `_findRetainCyclesInObject` 方法中，访问树中每一条路径查看是否有循环引用，它以栈替代了递归方案，避免了多次递归导致的栈溢出，同时每次出栈时使用 `autoreleasepool` 避免了在这之中的产生的大量临时对象造成的内存激增。采用迭代器 `FBNodeEnumerator` 包装每一个节点，这样在迭代器内部保存未入栈的对象，避免一下将大量的子节点都入栈，提升查找效率。

重点介绍出栈时的相关逻辑：

* 取出栈顶对象
* 如果当前对象未被访问过但之前查找过，说明已访问过相关子树，则直接出栈；
* 取出栈顶对象的下一个子节点：
  * 如果对象为空说明当前对象无下一个子节点，直接出栈；
  * 如果当前对象在 `objectsOnPath` 不存在，说明引用关系正常，将子节点入栈；
  * 如果当前对象之前访问过，说明有循环引用，栈顶到之前访问过的节点之前的对象全都是循环引用关系链的节点，将其保存同时并不入栈避免重复入栈造成死循环。

例如下图在节点 7 作为栈顶对象时，此时 `objectsOnPath` 为 `[1, 2,  4, 7]`，节点 7 的子对象 2 出现过，那么从 `[2, 4, 7]` 则是循环引用链的相关对象。

![image-20230815173350242](/images/blog/image-20230815173350242.png)

```objc
- (NSSet<NSArray<FBObjectiveCGraphElement *> *> *)_findRetainCyclesInObject:(FBObjectiveCGraphElement *)graphElement
                                                                 stackDepth:(NSUInteger)stackDepth
{
  NSMutableSet<NSArray<FBObjectiveCGraphElement *> *> *retainCycles = [NSMutableSet new];
  FBNodeEnumerator *wrappedObject = [[FBNodeEnumerator alloc] initWithObject:graphElement];

  NSMutableArray<FBNodeEnumerator *> *stack = [NSMutableArray new];
  // 当前访问的路径
  NSMutableSet<FBNodeEnumerator *> *objectsOnPath = [NSMutableSet new];

  [stack addObject:wrappedObject];

  while ([stack count] > 0) {
    @autoreleasepool {
      FBNodeEnumerator *top = [stack lastObject];

      // 避免重复遍历子树
      if (![objectsOnPath containsObject:top]) {
        if ([_objectSet containsObject:@([top.object objectAddress])]) {
          [stack removeLastObject];
          continue;
        }
        [_objectSet addObject:@([top.object objectAddress])];
      }

      [objectsOnPath addObject:top];

      FBNodeEnumerator *firstAdjacent = [top nextObject];
      if (firstAdjacent) {
        BOOL shouldPushToStack = NO;
        if ([objectsOnPath containsObject:firstAdjacent]) {
          // 发现循环引用
          NSUInteger index = [stack indexOfObject:firstAdjacent];
          NSInteger length = [stack count] - index;
          // 对象可能被销毁在查询下标过程中
          if (index == NSNotFound) {
            shouldPushToStack = YES;
          } else {
            NSRange cycleRange = NSMakeRange(index, length);
            NSMutableArray<FBNodeEnumerator *> *cycle = [[stack subarrayWithRange:cycleRange] mutableCopy];
            [cycle replaceObjectAtIndex:0 withObject:firstAdjacent];
            [retainCycles addObject:[self _shiftToUnifiedCycle:[self _unwrapCycle:cycle]]];
          }
        } else {
          // 正常节点，入栈
          shouldPushToStack = YES;
        }

        if (shouldPushToStack) {
          if ([stack count] < stackDepth) {
            [stack addObject:firstAdjacent];
          }
        }
      } else {
        // 当前节点的子节点遍历完了，出栈
        [stack removeLastObject];
        [objectsOnPath removeObject:top];
      }
    }
  }
  return retainCycles;
}
```

### 如何获取对象强引用指针

`FBObjectiveCGraphElement` 的 `allRetainedObjects` 方法返回了对象的所有的强引用。上文也提到过，不同的对象有不同的获取实现，这也是能够监测循环引用的关键：

#### 获取 `NSObject` 的强引用：

获取 `NSObject` 对象的强引用在 `FBObjectiveCObject` 类中实现，它利用 Runtime 的一些函数获得了 `ivars` 和 `ivarLayout`（区分了哪些是强引用和弱引用），它的几个核心方法逻辑如下（按调用顺序）：

* `allRetainedObjects`：获取类的强引用布局信息，通过 `object_getIvar` 或偏移得到实际的对象，并将其封装为 `FBObjectiveCGraphElement` 类型，最后对是否是桥接对象，元类对象，可枚举对象进行处理。

* `FBGetObjectStrongReferences`：从子类到父类依次获取强引用，由 `FBObjectReference` 封装，并进行缓存。
* `FBGetStrongReferencesForClass`：从类中获取它指向的所有引用，包括强引用和弱引用(`FBGetClassReferences`方法)；通过 `class_getIvarLayout` 获取关于 ivar 的描述信息，以若干组 `\xnm` 形式表示，n 表示 n 个非强属性，m 表示有 m 个强属性；通过 `FBGetMinimumIvarIndex` 获取变量索引的最小值；通过 `FBGetLayoutAsIndexesForDescription` 获取所有强引用的 Range（为两个索引）；最后使用 `NSPredicate` 过滤所有不在强引用 Range 中的属性。
* `FBGetClassReferences`：调用 Runtime 的 `class_copyIvarList` 获取类的所有 `ivar`，并封装成 `FBIvarReference` 对象，其中包含了实例变量名称、类型（根据 `typeEncoding` 区分）、偏移、索引等信息；如果是结构体则遍历检查它是否包含其他的对象(`FBGetReferencesForObjectsInStructEncoding` 方法)。

具体分析可以参考 [检测 NSObject 对象持有的强指针](https://draveness.me/retain-cycle2/)

#### 获取 `block` 的强引用：

获取 `block` 对象的强引用在 `FBObjectiveCBlock` 类中实现，它利用了 `dispose_helper` 函数会向强引用对象发送 `release` 消息实现，而对弱引用不会做任何处理，下面是一些主要函数与类：

* `allRetainedObjects`：获取 block 的强引用数组（`FBGetBlockStrongReferences` 方法），并封装为 `FBObjectiveCGraphElement` 类型，这与 `FBObjectiveCObject` 的处理过程类似。
* `FBGetBlockStrongReferences`：获取强引用的下标（`_GetBlockStrongLayout`  方法），将 block 转换为 `void **blockReference`，从而通过下标获取到强引用对象。
* `FBBlockStrongRelationDetector`：在使用 `dispose_helper` 时使用的伪装成被引用的类，重写了 `release` 方法（只是做标记，不真正 `release`），同时含有一些必要属性兼容了引用对象是 block 的情况。

```objc
- (oneway void)release
{
  _strong = YES;
}

- (oneway void)trueRelease
{
  [super release];
}
```

* `_GetBlockStrongLayout`：如果有 C++ 的构造解析器，说明它持有的对象可能没有按照指针大小对齐，或者如果没有 `dispose` 函数，说明它不会持有对象，这两种情况直接返回 `nil`；将 `block` 转化为 `BlockLiteral` 类型，获得 `block` 所占内存大小，除以函数指针大小，并向上取整，得到可能有的引用对象个数（实际肯定小于这个数，因为含有 block 自身的一些属性，如 `isa`，`flag`，`size` 等）。不过由于其指针对齐与捕获变量排序机制（一般按`__strong`、``__block`、`__weak` 排序），我们以此创建的 `FBBlockStrongRelationDetector` 数组也与强引用的地址对齐，调用 `dispose_helper` 并将被标记的下标保留并返回。

具体分析可以参考 [iOS 中的 block 是如何持有对象的](https://draveness.me/block-retain-object/)

* 获取 `NSTimer` 的强引用：

获取 `NSTimer` 的强引用在 `FBObjectiveCNSCFTimer` 中实现，它将 `NSTimer` 转换为 `CFTimer`，如果它有 `retain` 函数，就假设它含有强引用对象，将 `target` 和 `userInfo` 分别将其以 `FBObjectiveCGraphElement` 包装并返回。

* 获取强引用关联对象：

在 `FBAssociationManager` 中提供了 `hook` 关联对象的 `objc_setAssociatedObject` 和 `objc_removeAssociatedObjects`，它将设置成 `retain` 策略的关联对象的 key 拷贝存储，最后通过拷贝的强引用的 key 通过 `objc_getAssociatedObject` 取出强引用（`associationsForObject`）。

* 可迭代对象如何处理

如果对象支持 `NSFastEnumeration` 协议，会遍历对象，将容器里的内容取出，以 `FBObjectiveCGraphElement` 封装。不过遍历过程中元素可能会改变，因此会如果取出失败会进行最大次数为 10 的重试机制。

```objc
NSInteger tries = 10;
for (NSInteger i = 0; i < tries; ++i) {
  NSMutableSet *temporaryRetainedObjects = [NSMutableSet new];
  @try {
    for (id subobject in self.object) {
      if (retainsKeys) {
        FBObjectiveCGraphElement *element = FBWrapObjectGraphElement(self, subobject, self.configuration);
        if (element) {
          [temporaryRetainedObjects addObject:element];
        }
      }
      if (isKeyValued && retainsValues) {
        FBObjectiveCGraphElement *element = FBWrapObjectGraphElement(self,
                                                                     [self.object objectForKey:subobject],self.configuration);
        if (element) {
          [temporaryRetainedObjects addObject:element];
        }
      }
    }
  }
  @catch (NSException *exception) {
    continue;
  }
  [retainedObjects addObjectsFromArray:[temporaryRetainedObjects allObjects]];
  break;
}
```

## 🔗

[1] [iOS端循环引用检测实战](https://toutiao.io/posts/msv1hlb/preview)

[2] [MLeaksFinder新特性](http://wereadteam.github.io/2016/07/20/MLeaksFinder2/#comments)

[3] [Automatic memory leak detection on iOS](https://engineering.fb.com/2016/04/13/ios/automatic-memory-leak-detection-on-ios/)

[4] [FBRetainCycleDetector](https://github.com/facebook/FBRetainCycleDetector)

[5] [检测 NSObject 对象持有的强指针](https://draveness.me/retain-cycle2/)

[6] [iOS 中的 block 是如何持有对象的](https://draveness.me/block-retain-object/)

[7] [runtime使用篇：class_getIvarLayout 和 class_getWeakIvarLayout](https://www.jianshu.com/p/6b218d12caae)

[8] [Swift静态代码监测工程实践](https://kingnight.github.io/programming/2023/02/20/Swift%E9%9D%99%E6%80%81%E4%BB%A3%E7%A0%81%E6%A3%80%E6%B5%8B%E5%B7%A5%E7%A8%8B%E5%AE%9E%E8%B7%B5.html#swiftlint%E7%AE%80%E4%BB%8B)

[9] [聊聊循环引用的监测](https://triplecc.github.io/2019/08/15/%E8%81%8A%E8%81%8A%E5%BE%AA%E7%8E%AF%E5%BC%95%E7%94%A8%E7%9A%84%E6%A3%80%E6%B5%8B/)

[10] [ObjC中的TypeEncodings](https://juejin.cn/post/6844903606403989517)
