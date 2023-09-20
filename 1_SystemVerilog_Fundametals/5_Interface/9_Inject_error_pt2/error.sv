`timescale 1ns/100ps

interface add_if;
	logic [3:0] a;
	logic [3:0] b;
	logic [4:0] sum;
	logic 		clk;
endinterface 

class transaction; // DUT 에 존재하는 모든 입출력 포트에 대한 변수들을 클래스 간의 공유 용도 
	randc bit [3:0] a;
	randc bit [3:0] b;
	bit [4:0] sum;

	function void display();
		$display ("a: %0d, b: %0d, sum: %0d", a,b,sum);
	endfunction

	virtual function transaction copy(); 	//랜덤 값이 아닌 직접 값을 넣을시 해당 함수 Virtual 선언
		copy = new();
		copy.a = this.a;
		copy.b = this.b;
		copy.sum = this.sum;
	endfunction
endclass

class error extends transaction; // child 클래스 생성후 a, b 포트에 제약 조건을 걸어 에러 inject 
	
	//constraint data_c {a == 0; b==0;}
   
   function transaction copy();
       copy = new();
       copy.a = 12;  //직접 값을 넣어 전달
       copy.b = 12;
       copy.sum = this.sum;
    endfunction

endclass


class generator; // 랜덤 값을 생상하고 IPC 즉 메일 박스를 통하여 드라이버에 전송
	transaction trans;
	mailbox #(transaction) mbx;
	event done;

	function new(mailbox #(transaction) mbx);
		this.mbx = mbx;
		trans = new();
	endfunction

	task run();
		for (int i=0; i<10; i++) begin
			trans.randomize();
			mbx.put(trans.copy);//Deep copy 로 메일 박스에 전송
			$display (" Send data to driver");
			trans.display();
			#20;
		end
		-> done;
	endtask

endclass

class driver; // Generator로부터 랜덤값을 수신하고 인터페이스를 통하여 DUT에 해당 신호 트리거
	virtual add_if aif;
	mailbox #(transaction) mbx;
	transaction data;
	event next;

	function new (mailbox #(transaction) mbx);
		this.mbx = mbx;
	endfunction

	task run();
		forever begin
			mbx.get(data);
			@(posedge aif.clk);
			aif.a <= data.a;
			aif.b <= data.b;
			$display("Interface Trigger");
			data.display();
		end
	endtask
endclass

module tb;
	add_if aif();
	driver drv;
	generator gen;
	error err;
	event done;

	mailbox #(transaction) mbx;

	add dut (.a(aif.a), .b(aif.b), .sum(aif.sum), .clk(aif.clk));

	initial begin
		aif.clk <= 0;
	end

	always #10 aif.clk = ~aif.clk;


	initial begin
		mbx = new();
		drv = new(mbx);
		gen = new(mbx);
		err = new();
		gen.trans = err;
		drv.aif = aif;
		done = gen.done;
	end

	initial begin
		fork
			gen.run();
			drv.run();
 		join_none
		   wait(done.triggered); //gen,drv 가 실행중이여도 gen의 done Flag 표시되면 종료
			$finish;
	end

	initial begin
		$fsdbDumpvars;	//Verdi 디비깅 파일 생성
		#200;
		$finish();
	end
endmodule

