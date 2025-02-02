---
title: "Xcode 中的调试技巧"
date: 2022-06-01 09:49:00
categories:
  - iOS
tags:
  - LLDB
  - Instrument
---

## 前言
```Xcode``` 内置了许多工具能够帮助开发者进行高效快速的 ```Debug```，例如 ```LLDB```、 ```Instruments```、```Debug View Hierarchy```、```Debug Memory Graph``` 等。本文将介绍 ```LLDB``` 中实用的命令，以及如何利用 ```Instruments``` 解决内存相关的问题。 <!-- more -->
## LLDB
```LLDB``` 是 ```LLVM``` 中的调试器组件，支持调试 ```C```、```Objective-C```、```C++``` 编写的程序，```Swift``` 社区维护了一个版本，增加了对该语言的支持，```LLDB``` 是 ```Xcode``` 的默认调试器。对于熟练使用 ```Xcode``` 的开发者来说，创建断点、使断点无效是一件再简单不过的事情，只需要的源代码的左侧行数点击即可。但是在 ```LLDB``` 还有许多提升开发效率的事，例如 ```frame、breakpoint```、```expression```、```image``` 等命令。
### expression
```expression``` 主要用于「在当前线程执行表达式，并显示其返回值」。其语法如下：
`expression <cmd-options> -- <expr>`
例如被大家所熟知的 `po`、`p` 都是关于 `expression` 的缩写形式
-   `po` 是 `expression -O --` 的缩写形式
-   `p` 是 `expression --` 的缩写形式
可以看到，主要有可选参数与表达式两部分；为了区分可选参数与表达式，采用 `--` 进行分割，下面列举常用的一些可选参数：
-   `-D`，设置最大递归深度解析层级
-   `-O`，打印特定语言的对象的 `description` 方法
-   `-T`，显示变量类型
-   `-f`，以特定格式化类型进行输出
-   `-i`，执行表达式时忽略断点触发
更多的可选参数可以通过 `help expression` 进行查看
同时，`expression` 还可以可以定义变量，但需在变量名前面加入 `$` 标识符，例如

在 ```Swift``` 中：

`expression var width: CGFloat = 20.0`

在 ```OC``` 中：

`expression NSArray *$array = @[@"one", @"two"];`

### 进程流程控制

<img src="/images/blog/image-20220420112717291.png" alt="image-20220420112717291" style="zoom:200%;" />

当程序运行或暂停时，在控制台上方会出现上图这 4 个按钮，这 4 个按钮分别对应着「进程暂停与继续」、「执行当前行」、「调入执行函数」、「跳出执行函数」，分别对应着以下 4 个命令：

1.  `process continue(continue)`
0.  `thread step-over(next、n)`
0.  `thread step in(step、s)`
0.  `thread step out(fin)`

断点对于调试来说是很重要的东西，只需要在 ```Xcode``` 源文件左侧点击即可添加断点，同时也会出现在 ```Breakpoint navigator``` 中：

<img src="/images/blog/image-20220511110055321.png" alt="image-20220511110055321" style="zoom:50%;" />

同时还可以添加列断点，如果你的一行代码中有几个表达式，你可能希望只停留在某一个表达式中，那么列断点就很有用了，右键想要断点的表达式，点击 ```Create Column Breakpoint``` 即可创建列断点。

<img src="/images/blog/image-20220512110941465.png" alt="image-20220512110941465" style="zoom:67%;" />

在 ```Breakpoint navigator``` 中点击左下角的 ```+``` 号，可以发现创建有 6 大类型的断点，不过主要来说可以分为两种：
-   异常、错误断点：捕获异常和错误，在将要发生 ```Crash``` 时，提前暂停并定位到有错误的代码中。
-   符号断点：即 ```Symbolic Breakpoint```，可以通过方法名称创建断点，当执行到对应的方法时，便会暂停。

<img src="/images/blog/image-20220512111557861.png" alt="image-20220512111557861" style="zoom:67%;" />

还可以使用 ```breakpoint``` 命令来进行对断点的管理，下面介绍一些常见的命令：

-   `breakpoint list` 显示断点列表
-   `breakpoint enable / disable / del <breakpointId>` 通过 id 开启、关闭、删除断点( ```id``` 即为 ```breakpoint list``` 显示的 ```id``` )
-   `breakpoint set <cmd-options>`

创建断点的方式有很多种，但最常见的是通过文件名与代码行数创建，或者是符号化进行创建：

-   `breakpoint set -f <fileName> -l <lineNum>` 通过文件名与代码行数创建
-   `breakpoint set -n <function_name>` 通过方法名创建

同时还可以在 ```Breakpoint navigator``` 中对断点进行编辑，给断点创建名称、断点触发执行条件、暂停前忽略次数、执行 ```Action```，以及执行完 ```Action``` 后继续执行。

<img src="/images/blog/image-20220518170038329.png" alt="image-20220518170038329" style="zoom:67%;" />

不过上述的功能都可以通过命令行实现，例如创建执行 ```Action``` 与 断点触发执行条件如下：

`breakpoint set -C <command> -c <condition expression> -n <function_name>`

更多功能可通过 `help breakpoint` 进行查看。

如果想观察某个值发生变化，那么 `watchpoint` 会非常有用，同样创建 `watchpoint` 有 2 种方式，在 debug 时右键属性并点击 `watch "<variable-name>"`。

<img src="/images/blog/image-20220512153529644.png" alt="image-20220512153529644" style="zoom:67%;" />

控制台则可以 `watchpoint set variable [-w <watch-type>] [-s <byte-size>] <variable-name>` 进行创建。

## 其他常见的命令

```frame``` 命令可以显示当前栈帧的一些信息：

-   `frame info`：显示栈帧所在位置
-   `frame variable <variableName>`：显示栈帧变量，如果没有 `<variableName>` 则显示栈帧的变量列表，别名 v

```thread``` 用于操作当前进程的一个或多个线程

-   `thread list`：显示所有线程
-   `thread info`：显示线程的额外概要
-   `thread backtrace` ：显示线程的调用栈
-   `thread continue`：继续执行一个或多个指定线程
-   `thread exception`：显示线程异常对象
-   `thread return`：提前返回一个栈帧，并可提供可选返回值

```process``` 在当前平台与进程交互

-   `process continue`：继续执行当前进程中的所有线程
-   `process interrupt`：中断当前进程
-   `process kill`：结束当前进程
-   `process status`：显示当前进程状态

```image``` 可以访问目标模块的信息（是 `target modules` 的缩写）

-   `image list`：列出当前可执行和依赖的共享库镜像
-   `image lookup`：根据参数查找其在可执行和依赖的共享库镜像的信息(如：地址、文件名、方法名、符号等)
-   `image search-paths`：搜索路径的配置项
-   `image show-unwind`：显示函数合成的 ```unwind``` 指令

```disassemble``` 显示当前 ```target``` 中的指定汇编指令，默认是当前线程和当前栈帧中的当前方法

-   `disassemble`：当前线程和当前栈帧中的当前方法的汇编指令
-   `disassemble -a <address-expression>`：从某一地址开始
-   `disassemble -n <function-name>`：从某一方法开始

最后，还可以利用 ```commond alias``` 或者编写 ```python``` 脚本来实现自己的 ```LLDB``` 命令。

## po & p & v

```po```、```p```、```v``` 都可以用来打印变量，那么它们有什么不同呢？

-   ```po``` 显示对象的 `debugDescription` 属性，系统会提供默认值，可以通过实现 `CustomDebugStringConvertible` 协议进行自定义。

```po``` 后面跟表达式，因此可以执行方法，赋值等操作。```po``` 的执行步骤分为两部分，第一步生成源代码，并在上下文中编译执行，第二步获取第一步返回的对象，并再次生成源代码并在上下文中编译执行，最后显示第二步返回的字符串。这里需要注意的是，为了能够使你的表达式能够被完整表达，```LLDB``` 没有采取直接解析和评估表达式本身，采用生成可编译的源代码进行处理，这种方式完全保留了代码本身。例如，你输入 ```po view```。

第一步生成的源代码为：


```
func __lldb_expr() { 
    __lldb_res = view
}
```

第二步生成的源代码为：

```
func __lldb_expr2() -> String {
    return __lldb_res.debugDescripution
}
```

<img src="/images/blog/image-20220522170206675.png" alt="image-20220522170206675" style="zoom:67%;" />

-   ```p``` 命令，```p``` 与 ```po``` 的输出略有不同，但都包含相同的信息，每个表达式结果都会被赋予增值名称，如 ```$R1```、```$R2``` 等，这些结果就会被存储起来，并可以像普通的对象一样使用。```p``` 命令执行分为 3 步，第一步与 ```po``` 命令相同，将表达式生成源代码，并进行编译执行，之后会进行动态类型解析，并将解析结果格式化。动态类型解析是由于其多态性，只有在运行时才能得知其运行时类型；对解析结果进行格式化是由于 ```Swift``` 标准库即使针对 ```Int```、```String``` 这样的简单类型，都进行了高度封装优化，因此其有复杂表达，所以需要进行格式化。

<img src="/images/blog/image-20220523174847611.png" alt="image-20220523174847611" style="zoom:35%;" />

-   ```v``` 命令，```v``` 命令的输出与 ```p``` 完全一样。但与 ```p``` 和 ```po``` 不同的是，```v``` 命令并不进行编译与执行代码，所以它非常快，它采用点和下标符来访问字段。```v``` 命令执行分为 4 步，首先会查询进程状态为了内存中定位变量，之后便从内存中读取变量，并对其执行动态类型检查，如果它有访问子属性，则多次进行内存读取变量以及动态类型检查。最后将结果进行格式化。

<img src="/images/blog/image-20220523180303016.png" alt="image-20220523180303016" style="zoom:35%;" />

## Debug View Hierarchy

首先从 ```Xcode``` 中的 `Product -> Scheme -> Edit Scheme -> Diagnostics` 中开启 `Malloc Stack Logging` 选项，并选择 `All Allocation and Free History`。这开启了创建堆栈信息调用日志，在 Debug 时便可通过对象的信息去查看其调用堆栈。

打开 ```Debug View Hierarchy```，便可发现在右侧的 ```Backtrace``` 中有了内容，如果你有约束冲突，或者想查看某个视图的创建信息，只需要在左侧的图层结构或者中间的图像选中你想要的即可。

![image-20220518192011839](/images/blog/image-20220518192011839.png)

同样的 ```LLDB``` 还给我们带来了更加强大的功能，可以达到不需要重新编译从而改变视图的一些行为，具体实现方法可以类似如下：

0.  定位到某个具体的对象，即从界面中选中某一个视图或者约束。
0.  按钮 ```commond + c``` 便可复制其带有类型的内存地址，这时便可以对它进行操作，具体的在控制台中，输入你想要改变的操作，如：

`e [((UIView *)0x7fa9320061a0) setBackgroundColor: [UIColor greenColor]]`

注意这里需要使用 ```Objective-C``` 的语法，因为 ```Swift``` 的安全性导致不能访问所有内容。

3.  这时你发现界面没有改变，需要刷新视图：

`e (void) [CATransaction flush];`

具体关于 ```Debug View Hierarchy``` 的更多用法可参考[这里](https://www.jianshu.com/p/9800c919e6cc)。

## Debug Memory Graph

点开 ```Debug Memory Graph```，会暂停进程，并显示当前堆的所有对象，并且会显示它们之间的所属关系和强引用与弱引用（深色的为强引用，浅色的为弱引用）。

如果你开启了 `Malloc Stack Logging`，也同样能看见对象的堆栈调用信息。

不仅如此，还可以发现内存泄漏，可以点开左下角的感叹号，仅筛选出内存泄漏对象。不过令人遗憾的是，```Debug Memory Graph``` 并不能显示出所有的内存泄漏问题。例如下图，在 ```SecondViewController``` 持有 ```block``` 与 ```block``` 中去持有 ```SecondViewController``` 中的 ```view```，这是经典的由 ```block``` 导致的循环引用，虽然 ```Debug Memory Graph``` 没有明确捕捉到，但是仍给我们排查提供了线索。

![image-20220519190816761](/images/blog/image-20220519190816761.png)

点击 ```Edit -> Export Memory Graph```，可以导出内存分布图文件。利用 ```vmmap```、```leaks```、```heap``` 等命令行工具可以进一步分析内存问题，具体分析可参考 [iOS 内存调试篇 -- memgraph](http://www.yuezyevil.com/2021/01/14/iOS%20%E5%86%85%E5%AD%98%E8%B0%83%E8%AF%95%E7%AF%87%20%E2%80%94%E2%80%94%20memgraph/)。

## Instruments

```Instruments``` 提供了一套丰富工具和模版去分析 应用的性能问题，常见的模版有：

| 名称             | 功能                                                         |
| ---------------- | ------------------------------------------------------------ |
| Leaks            | 一般的查看内存使用情况，检查泄漏的内存，并提供了所有活动的分配和泄漏模块的类对象分配统计信息以及内存地址历史记录。 |
| Time Profiler    | 执行对系统的 CPU上运行的进程低负载时间为基础采样。           |
| Allocations      | 跟踪过程的匿名虚拟内存和堆的对象提供类名和可选保留/释放历史。 |
| Activity Monitor | 显示器处理的 CPU、内存和网络使用情况统计。                   |
| Blank            | 创建一个空的模板，可以从 Library 库中添加其他模板。          |
| Core Data        | 监测读取、缓存未命中、保存等操作，能直观显示是否保存次数远超实际需要。 |
| Network          | 跟踪 TCP/IP 和 UDP/IP 连接。                                 |
| Engergy Log      | 应用的电量消耗情况。                                         |

下面基于 ```Time Profiler``` 模版，梳理如何使用 ```Instruments```：

0.  首先选中 ```Time Profiler```，会出现空的配置页
0.  在左上方中选择分析的设备以及应用
0.  点击开始，这时便可操作测试你的应用。
0.  当操作完成，点击暂停或结束，这时便可针对有问题的数据进行分析。

![image-20220531171357436](/images/blog/image-20220531171357436.png)

选取你认为可疑的时间段，例如大量占用 ```CPU``` 的时间段，其次逐步根据去排查代码问题，例如主线程中有耗时操作。

更推荐看下 ```WWDC``` 中关于 ```Instruments``` 的介绍 [WWDC2019 - Get Started with Instruments](https://developer.apple.com/videos/play/wwdc2019/411/)，笔者只是简单的概述。关于 ```Instruments```，它没有记录所有的调用栈帧，而是在每秒去记录许多次栈帧快照，这是为了更好的性能体验。

## 无限调试

还有一个关于调试的小技巧，如果你希望不使用数据线连接电脑，可以采用局域网的形式连接，同样也可以进行真机运行与调试。具体在 ```Device``` 列表中右键设备并点击 ```Connect via IP Address```。

<img src="/images/blog/image-20220531144036056.png" alt="image-20220531144036056" style="zoom:67%;" />

除此之外在菜单栏中选中 ```Debug``` 的 ```Attach to Process by Pid or Name``` 或者 ```Attach to Process``` ，通过列表选中想要附加的进程，就可以不用想要 ```Debug``` 的时候再次手动 ```Run``` 一次。不过这两种方式，都会有一定性能损耗，会导致响应时间慢问题。

## 总结

本文总结了 ```LLDB``` 的一些常见命令，据统计，一名程序员大约有 70% 的时间都在 ```Debug```，如果能够熟练使用它们，无疑会极大提升编程效率。同时还介绍了如 ```Debug View Hierarchy```、```Debug Memory Graph``` 的常见用法。特别是 ```Debug Memory Graph```，因为内存问题往往是不易察觉且不易找到的，好好利用它，能够让我们对内存问题研究的更加深入。最后是 ```Instruments```，它里面有许多工具，针对各方面的性能问题都有所涵盖，```Jonathan Levin``` 称，与其他操作系统相比，```Instruments``` 是最好的调试和性能剖析工具。

## 🔗

[与调试器共舞 - LLDB 的华尔兹](https://objccn.io/issue-19-2/)

[用 LLDB 调试 Swift 代码](https://medium.com/@vin.pradeilles/advanced-debugging-with-xcode-5e6c8dabd311)

[WWDC2018 - 412 通过 Xcode 和 LLDB 进行高级调试](https://developer.apple.com/videos/play/wwdc2018/412/)

[WWDC2019 - 429 LLDB 不限于 “po”](https://developer.apple.com/videos/play/wwdc2019/429/)

[WWDC2019 - 411 Get Started with Instruments](https://developer.apple.com/videos/play/wwdc2019/411/)

《深入解析 Mac OS X & iOS 操作系统》
