# SF-CB 轻载时延改进研究

本目录与根目录现有协议实现隔离，不修改原有时延实验代码。研究对象只有
SF-CB，并用相同到达轨迹比较四种MAC机制：

1. `baseline`：原始固定概率、分时隙SF-CB；
2. `fast_first`：节点从空队列变为非空时，该HOL包第一次以概率1发送；
   若失败，之后恢复配置中的普通 `q`；
3. `unslotted`：取消198 us连接时隙边界。新HOL在到达所处的9 us物理
   边界立即发送持续18 us（2个毫米波slot）的RTS；只有RTS发送区间重叠
   才按经典碰撞模型全部失败。RTS结束后等待CTS响应或完整扇区扫描超时；
   AP依次扫描8个扇区发送CTS，发送RTS中的STA因半双工听不到本扇区CTS，
   其余STA仅在CTS SINR达标时设置NAV。成功STA随后定向发送DATA，AP定向
   接收并按DATA SINR判定；失败后的HOL按 `q` 在后续9 us物理边界重试；
4. `batch_clear`：预约规则与原始SF-CB相同；唯一节点预约成功后，将连接
   建立时该节点队列内的所有包作为一个快照，在一次连接中顺序发送完毕。
   DATA阶段新到达的包不追加到当前批次。

所有协议沿用原始统计定义：

```text
queue_delay = HOL_start - arrival
access_delay = completion - HOL_start
end_to_end_delay = completion - arrival
```

批量发送时，批次中第一个包承担预约接入时间；后续包在前一个包完成时
成为HOL，因此其接入时延为自己的DATA时长，且逐包严格满足：

```text
end_to_end_delay = queue_delay + access_delay
```

## 运行

在MATLAB中执行：

```matlab
run('sf_cb_lightload_study/run_all.m')
```

默认扫描：

```text
lambda = [1 3 5] pkt/STA/s
M      = 1:6
```

每个 `(协议,lambda,M)` 先对普通 `q` 粗扫并局部细扫，再使用独立种子评估。
候选点本身及相邻点均需通过完成率门槛；此外，候选 `q` 必须能在5组
独立随机序列下，于2 s内从12个节点同时竞争形成的碰撞组中完全恢复。
该压力测试用于排除轻载均值虽低、但偶发进入长碰撞雪崩的高 `q`。
输出位于本目录的 `results/<timestamp>/`：

```text
condition_summary.csv
run_summary.csv
q_scan.csv
q_validation.csv
packet_delays.csv
study_results.mat
manifest.json
figures/sf_cb_lightload_delay_comparison.png
figures/sf_cb_lightload_delay_comparison.pdf
verification/tests.csv
```

主图为一个3×3布局：每一行对应一个到达率，每一列分别为平均端到端、
排队和接入时延。
