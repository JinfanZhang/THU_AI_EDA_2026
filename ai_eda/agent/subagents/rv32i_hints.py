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


def checklist_for(project: dict | None) -> str:
    """只对 RV32I 系列项目追加提示。"""
    project_id = str((project or {}).get("id") or "")
    if project_id.startswith("rv32i"):
        return RV32I_L0_CHECKLIST
    return ""
