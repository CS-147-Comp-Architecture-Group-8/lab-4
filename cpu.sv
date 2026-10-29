`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/13/2026 05:19:10 PM
// Design Name: 
// Module Name: cpu
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module cpu(

    input  logic        rst_n,
    input  logic        clk,

    output logic [31:0] imem_addr,
    input  logic [31:0] imem_insn,

    output logic [31:0] dmem_addr,
    inout  wire  [31:0] dmem_data,
    output logic        dmem_wen
    
    
    );
    
    // =====================================================
    // INSTRUCTION FETCH (IF)
    // =====================================================

    // Program Counter (PC) stores the address of the
    // instruction currently being fetched
    
    logic [31:0] pc;
    
    // Reset PC to 0. Otherwise, advance 4 bytes per cycle
    // because each instruction is 32 bits (4 bytes).
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            pc <= 32'd0;
        else if (!stall) // holds the PC assignment (FETCH) during stall
            pc <= pc + 32'd4;
    end
    
    // Send the current PC to instruction memory.
    assign imem_addr = pc;
    
    // =====================================================
    // IF/ID PIPELINE REGISTER
    // =====================================================

    // Preserve the fetched instruction and its address
    // while the PC advances to the next instruction.
    
    logic [31:0] if_id_insn;
    logic [31:0] if_id_pc;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            if_id_insn <= 32'h00000013;
            if_id_pc   <= 32'd0;
        end
        else if (!stall) begin // keeps prior instruction in Decode during stall
            if_id_insn <= imem_insn;
            if_id_pc   <= pc;
        end
    end
    
    // =====================================================
    // INSTRUCTION DECODE (ID)
    // =====================================================

    // Extract the source register, destination register,
    // and immediate value from the fetched instruction.
    
    logic [4:0] id_rs1;
    logic [4:0] id_rd;
    logic [31:0] id_imm;
    
    assign id_rs1 = if_id_insn[19:15];
    assign id_rd  = if_id_insn[11:7];
    
    // Sign-extend the 12-bit immediate to 32 bits.
    // Repeating bit 31 preserves negative values.
    assign id_imm = {{20{if_id_insn[31]}}, if_id_insn[31:20]};
    
    logic       id_is_alu;
    logic [3:0] id_alu_op;
    
    always_comb begin
        // Default values
        id_is_alu = 1'b0;
        id_alu_op = 4'b0000;
    
        // Check for I-type ALU opcode
        if (if_id_insn[6:0] == 7'b0010011) begin
    
            case (if_id_insn[14:12])
    
                // ADDI
                3'b000: begin
                    id_is_alu = 1'b1;
                    id_alu_op = 4'b0000;
                end
    
                // SLTI
                3'b010: begin
                    id_is_alu = 1'b1;
                    id_alu_op = 4'b0001;
                end
    
                // SLTIU
                3'b011: begin
                    id_is_alu = 1'b1;
                    id_alu_op = 4'b0010;
                end
    
                // XORI
                3'b100: begin
                    id_is_alu = 1'b1;
                    id_alu_op = 4'b0011;
                end
    
                // ORI
                3'b110: begin
                    id_is_alu = 1'b1;
                    id_alu_op = 4'b0100;
                end
    
                // ANDI
                3'b111: begin
                    id_is_alu = 1'b1;
                    id_alu_op = 4'b0101;
                end
    
                // SLLI
                3'b001: begin
                    if (if_id_insn[31:25] == 7'b0000000) begin
                        id_is_alu = 1'b1;
                        id_alu_op = 4'b0110;
                    end
                end
    
                // SRLI and SRAI
                3'b101: begin
                    if (if_id_insn[31:25] == 7'b0000000) begin
                        id_is_alu = 1'b1;
                        id_alu_op = 4'b0111; // SRLI
                    end
                    else if (if_id_insn[31:25] == 7'b0100000) begin
                        id_is_alu = 1'b1;
                        id_alu_op = 4'b1000; // SRAI
                    end
                end
    
                default: ;
            endcase
        end
    end
    
    
    // =====================================================
    // REGISTER FILE
    // =====================================================

    // 32 general-purpose registers, each 32 bits wide
    logic [31:0] registers [0:31];
    
    logic [31:0] id_rs1_value;
    // Read the source register during Decode.
    // Register x0 is hardwired to zero in RISC-V.
    assign id_rs1_value = (id_rs1 == 5'd0)
                        ? 32'd0
                        : registers[id_rs1];
                        
                   
    // =====================================================
    // ID/EX PIPELINE REGISTER
    // =====================================================

    // Preserve the operands, destination register, and
    // instruction validity for the Execute stage.
    logic [31:0] id_ex_rs1_value;
    logic [31:0] id_ex_imm;
    logic [4:0]  id_ex_rd;
    logic        id_ex_is_alu;
    logic [3:0]  id_ex_alu_op;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_ex_rs1_value <= 32'd0;
            id_ex_imm       <= 32'd0;
            id_ex_rd        <= 5'd0;
            id_ex_is_alu    <= 1'b0;
            id_ex_alu_op    <= 4'b0000;
        end
    // =====================================================
    // Bubble insertion into ID/EX
    // =====================================================
        else if (stall) begin
            // Bubble means no instruction executes
            id_ex_rs1_value <= 32'd0;
            id_ex_imm       <= 32'd0;
            id_ex_rd        <= 5'd0;
            id_ex_is_alu    <= 1'b0;
            id_ex_alu_op    <= 4'b0000;
        end else begin
            id_ex_rs1_value <= id_rs1_value;
            id_ex_imm       <= id_imm;
            id_ex_rd        <= id_rd;
            id_ex_is_alu    <= id_is_alu;
            id_ex_alu_op    <= id_alu_op;
        end
    end
    
    // =====================================================
    // EXECUTE (EX)
    // =====================================================

    // The ALU performs addition for ADDI instructions.
    // This is combinational logic: its output depends
    // directly on the current operand values.
    
logic [31:0] ex_result;

always_comb begin
    case (id_ex_alu_op)

        // ADDI
        4'b0000: ex_result = id_ex_rs1_value + id_ex_imm;

        // SLTI (Signed)
        4'b0001: ex_result = $signed(id_ex_rs1_value) < $signed(id_ex_imm);

        // SLTIU (Unsigned)
        4'b0010: ex_result = id_ex_rs1_value < id_ex_imm;

        // XORI
        4'b0011: ex_result = id_ex_rs1_value ^ id_ex_imm;

        // ORI
        4'b0100: ex_result = id_ex_rs1_value | id_ex_imm;

        // ANDI
        4'b0101: ex_result = id_ex_rs1_value & id_ex_imm;

        // SLLI
        4'b0110: ex_result = id_ex_rs1_value << id_ex_imm[4:0];

        // SRLI
        4'b0111: ex_result = id_ex_rs1_value >> id_ex_imm[4:0];

        // SRAI
        4'b1000: ex_result = $signed(id_ex_rs1_value) >>> id_ex_imm[4:0];

        // Default
        default: ex_result = 32'b0;

    endcase
end

    
    // =====================================================
    // EX/MEM PIPELINE REGISTER
    // =====================================================

    // Preserve the ALU result, destination register,
    // and valid-ADDI flag for the Memory stage.
    logic [31:0] ex_mem_result;
    logic [4:0]  ex_mem_rd;
    logic ex_mem_is_alu;
    
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ex_mem_result  <= 32'd0;
            ex_mem_rd      <= 5'd0;
            ex_mem_is_alu <= 1'b0;
        end
        else begin
            ex_mem_result  <= ex_result;
            ex_mem_rd      <= id_ex_rd;
            ex_mem_is_alu  <= id_ex_is_alu;
        end
    end
    
    
    // =====================================================
    // MEMORY (MEM) / MEM-WB PIPELINE REGISTER
    // =====================================================

    // ADDI does not access data memory.
    // Pass the ALU result and destination information
    // through this stage to Write Back.
    
    logic [31:0] mem_wb_result;
    logic [4:0]  mem_wb_rd;
    logic mem_wb_is_alu; //stall flag for WriteBack
    
    // =====================================================
    // STALL
    // =====================================================
    // Detects when Decode needs a register from a prior instruction
    logic stall; // stall bit (0 means pipeline can proceed; 1 means Decode must wait)
    
    // Stall if Decode contains addi, reads register that is not x0,
    // and a prior instruction in EX, MEM, or WB will write to same register
    assign stall = id_is_alu && (id_rs1 != 5'd0) && 
    (   // stall if EX has addi & destination register is not x0 & 
        // decode reads the register that EXE will write
        (id_ex_is_alu && (id_ex_rd != 5'd0) && (id_rs1 == id_ex_rd))
        ||
        // stall if MEM has addi & destination register is not x0 &
        // DEC reads register that MEM will write
        (ex_mem_is_alu && (ex_mem_rd != 5'd0) && (id_rs1 == ex_mem_rd))
        ||
        // stall if WB has addi & assoc register is not x0 &
        // DEC reads from register that WB will write
        (mem_wb_is_alu && (mem_wb_rd != 5'd0) && (id_rs1 == mem_wb_rd))
     );
        
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mem_wb_result  <= 32'd0;
            mem_wb_rd      <= 5'd0;
            mem_wb_is_alu <= 1'b0;
        end
        else begin
            mem_wb_result  <= ex_mem_result;
            mem_wb_rd      <= ex_mem_rd;
            mem_wb_is_alu <= ex_mem_is_alu;
        end
    end
    
    // =====================================================
    // WRITE BACK (WB)
    // =====================================================
    
    integer i;

    // Initialize the register file during reset.
    // Write the completed result to its destination
    // register on the rising clock edge.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 0; i < 32; i = i + 1)
                registers[i] <= 32'd0;
        end
        else begin
            // implicitly blocks writes to x0
            if (mem_wb_is_alu && mem_wb_rd != 5'd0)
                registers[mem_wb_rd] <= mem_wb_result;
        end
    end
    
    // =====================================================
    // CLOCK CYCLE COUNTER
    // =====================================================

    // Track the number of clock cycles since reset.
    // This counter increments independently of the PC.
    logic [15:0] cycle_count;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cycle_count <= 16'd0;
        else
            cycle_count <= cycle_count + 16'd1;
    end
    
    // =====================================================
    // DATA MEMORY INTERFACE
    // =====================================================

    // ADDI does not read or write data memory.
    // Disable writes and leave the bidirectional bus
    // undriven until memory operations are supported.
    
    assign dmem_addr = 32'd0;
    assign dmem_wen  = 1'b0;
    assign dmem_data = 32'bz;
    
    // =====================================================
    // SIMULATION TRACES
    // =====================================================

    // File operations are used only during simulation.
    // Excluding them from synthesis allows Vivado to
    // generate hardware from the CPU design.
    `ifndef SYNTHESIS
    
    // Record each fetched instruction address.
    integer pc_trace_file;
    
    initial begin
        pc_trace_file = $fopen("pc_trace.txt", "w");
    end
    
    always @(posedge clk) begin
        if (rst_n && pc_trace_file != 0) begin
            $fdisplay(pc_trace_file, "%08h", pc);
            $fflush(pc_trace_file);
        end
    end
    
    `endif
    
    // Register write trace - simulation only
    `ifndef SYNTHESIS
    // Record each valid register write.
    integer reg_trace_file;
    
    initial begin
        reg_trace_file = $fopen("reg_trace.txt", "w");
    end
    
    always @(posedge clk) begin
        if (rst_n && mem_wb_is_alu &&
            mem_wb_rd != 5'd0 && reg_trace_file != 0) begin
    
            $fdisplay(reg_trace_file, "%0d %08h",
                      mem_wb_rd, mem_wb_result);
                      
            $fflush(reg_trace_file);
        end
    end
    
    `endif
    
    
endmodule