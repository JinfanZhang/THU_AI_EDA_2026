"""RV32I 流水线的战术提示（供 Diagnoser / Patch Agent 复用）。

这些提示只描述「已知容易错的实现要点」，不包含参考答案，也不替代 Spec：
它们随系统提示注入，帮助修复阶段快速排除常见根因。
"""

RV32I_L0_CHECKLIST = """If the project is an RV32I processor, apply these hard checks when diagnosing:
- Load-use stall: when a load in EX is consumed by the instruction in ID, hold PC, IF/ID and ID/EX for exactly one cycle and inject a bubble into EX; never clear a valid instruction because of a stall.
- Forwarding: implement BOTH EX/MEM -> EX and MEM/WB -> EX paths; EX/MEM has priority over MEM/WB; never forward when the destination register is x0 or when the source register field is x0.
- Branch/JAL/JALR: resolved in EX; on taken, flush the two younger instructions (IF/ID and ID/EX), set PC to the target; JALR target = (rs1 + imm) & 32'hffff_fffe.
- Halt: only the WB stage may set halted/exit_code, and only for a committed ECALL; once halted, freeze PC fetch and stop retiring new instructions.
- Reset: synchronous active-low reset; every registered output (including dmem_valid) must be 0 during reset and before the first reset edge, so no access may be issued while rst_n is low.
- Single-cycle memory model: imem/dmem respond in the same cycle; do not insert extra wait states or register the response.
"""

# iverilog 12（教师 TB 用 -g2012 编译）不会支持全部 SystemVerilog；
# 这几条是实测最容易撞上的语法限制，写进角色提示可以少走几轮修复。
IVERILOG_RTL_HINTS = """Icarus Verilog 12 compile constraints (the teacher TB is compiled with -g2012):
- Variable part-selects such as `vec[8*i +: 8]` inside a procedural for loop are NOT supported; unroll the loop by hand or use a shift-and-mask temporary.
- "constant selects in always_* processes are not currently supported" comes from indexing an array with a constant inside always_comb/always_ff; use a packed vector, a generate loop with one always block per element, or a temporary.
- `break` and `continue` are NOT supported: restructure loops with a found-flag or exit-free if/else chains.
- Assignment to an entire array or an array slice (e.g. `mem <= '{default:0};` or `arr[3:0] <= ...`) is NOT supported; clear each element explicitly in a for loop with a variable index, or use packed vectors.
- No `inside`, `assert`, `class`, `interface`, packed structs with arrays, `$readmemh`, or nested unpacked arrays.
- Declare every signal once: do not redeclare a port name in the module body.
- Prefer plain `logic` vectors, `always_ff` with an explicit reset branch, and hand-unrolled assignments over nested loops; keep each file under ~600 lines.
"""


RV32I_L2_PREDICTOR = """If the project is RV32I L2 (dynamic branch prediction), these rules come straight from the spec:
- dbg_features is the constant 3'b011 for L2 (001 = L1, 111 = L3); it must be valid from time 0 and never change dynamically or be faked.
- BTB: 16 entries, direct-mapped, index PC[5:2], tag PC[31:6]; each entry holds valid, tag, 32-bit target and control type. Reset makes every entry invalid.
- BHT: 16 entries of 2-bit saturating counters, index PC[5:2], reset value 2'b01 (weakly not-taken). 00/01 predict Not Taken, 10/11 predict Taken.
- Predict at IF: on BTB hit, a conditional branch predicts the BTB target when BHT says Taken, otherwise PC+4; JAL/JALR predict the BTB target. BTB miss always predicts PC+4.
- Carry original PC, predicted next PC and a valid bit with the instruction to EX; compare the actual next PC against the prediction. Any mismatch (wrong direction OR wrong target) is a mispredict: flush every younger valid entry, cancel its architectural writeback, store and ECALL, and redirect PC. A correctly predicted taken branch must NOT flush again.
- BTB allocation: allocate a conditional branch only when it was a BTB miss and actually taken; a not-taken conditional never allocates. Allocate/update JAL/JALR on first resolve or when the target changes. Squashed younger control transfers must not write BTB/BHT; correctly predicted ones still update BHT.
- Same-cycle lookup vs write: produce this cycle's prediction from the OLD entry first, then apply this cycle's resolve update.
- Only control transfers that actually reach resolve (not killed by an older mispredict) may set dbg_bp_resolve / dbg_bp_mispredict.
- Training target: after warm-up, 64 resolved control transfers with at most 8 mispredicts and 132 retired instructions.
- Keep the L1 base and I/D cache behavior intact; L2 adds prediction on top of a working L1, do not rewrite the caches or the pipeline stages.
"""


def checklist_for(project: dict | None) -> str:
    """只对 RV32I 系列项目追加提示。"""
    project_id = str((project or {}).get("id") or "")
    if not project_id.startswith("rv32i"):
        return ""
    parts = [RV32I_L0_CHECKLIST, IVERILOG_RTL_HINTS]
    if project_id in {"rv32i5_predict", "rv32i5_ooo"}:
        parts.append(RV32I_L2_PREDICTOR)
    return "\n".join(parts)
