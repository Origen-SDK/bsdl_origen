module BsdlOrigen
  IN0  = 0
  IN1  = 1
  OUT0 = 2
  OUT1 = 3
  XXX  = 4 # input mode, unknown input data
  IN0_OUT1 = 5
  IN1_OUT0 = 6
  OUT0_IN1 = 7
  OUT1_IN0 = 8

  class BSDLcell
    attr_accessor :num, :cell, :port, :function, :safe, :ccell, :dsval, :rslt, :state, :compare, :access_cnt, :description

    def initialize(_info_a)
      @num         = _info_a[0].to_i # cell num
      @cell        = _info_a[1].to_s # cell type BC_0 - BC_99
      @port        = _info_a[2].to_s # port name
      @function    = _info_a[3].to_s # INPUT, BIDIR, OUTPUT2, OUTPUT3, CONTROL, CONTROLR, INTERNAL
      @safe        = _info_a[4].to_s # values that turns off driver in control cell
      @ccell       = -1              # controlling cell number for I/O direction
      @dsval       = ''              # disabling (input) value
      @rslt        = ''              # result if disabled (input = Z)

      @state       = "#{_info_a[4]}"
      @access_cnt  = 0
      @compare     = nil

      if _info_a.size > 4
        @ccell  = _info_a[5].to_i
        @dsval  = _info_a[6].to_s
        @rslt   = _info_a[7].to_s
      end

      @description = ''
      if @function =~ /(CONTROL|control)/
        @description = "C[#{@num}]_IBE<#{@safe}>"
      elsif @function =~ /(INPUT|input)/
        @description = "I[#{@num}][#{@port}]"
      elsif @function =~ /(OUTPUT|output)/
        @description = "O[#{@num}][#{@port}]_C<#{@ccell}>"
      elsif @function =~ /(BIDIR|bidir)/
        @description = "B[#{@num}][#{@port}]_C<#{@ccell}>"
      end
    end # initialize

    def info
      "#{@num},#{@cell},#{@port},#{@function},#{@safe},#{@ccell},#{@dsval},#{@rslt},STATE<#{@state}>,#{@description},#{@access_cnt}"
    end
  end # class BSDLcell

  class BSDLport
    attr_accessor :function_control, :function_input, :function_output, :function_bidir, :diffport, :state

    def initialize
      @function_control = nil
      @function_input   = nil
      @function_output  = nil
      @function_bidir   = nil
      @diffport         = nil
      @state            = XXX
      @ibe              = nil
      @obe              = nil
    end

    def info
      _ostr = ''
      unless @function_control.nil?
        _ostr.concat("CONTROL \t\t#{@function_control.info}\n")
      end
      unless @function_input.nil?
        _ostr.concat("INPUT   \t\t#{@function_input.info}\n")
      end
      unless @function_output.nil?
        _ostr.concat("OUTPUT  \t\t#{@function_output.info}\n")
      end
      unless @function_bidir.nil?
        _ostr.concat("BIDIR   \t\t#{@function_bidir.info}\n")
      end
      unless @diffport.nil?
        _ostr.concat("DIFFPORT\t\t#{@diffport}\n")
      end
      _ostr.concat("STATE   \t\t#{@state}")
    end

    def update_function_state(_istate, _ostate)
      if !@function_bidir.nil?
        if @function_control.state == @ibe
          @function_bidir.state = _istate.to_s
        else
          @function_bidir.state = _ostate.to_s
        end
      else
        unless @function_input.nil?
          @function_input.state = _istate.to_s
          unless @function_control.nil?
            if @function_control.state == @ibe
              @function_input.compare = nil
            end
          end
        end
        unless @function_output.nil?
          @function_output.state = _ostate.to_s
          unless @function_control.nil?
            if @function_control.state == @obe
              @function_input.compare = _ostate.to_s
            end
          end
        end
      end
    end

    def get_ibe_obe
      if @ibe.nil?
        unless @function_control.nil?
          if !@function_bidir.nil?
            @ibe = @function_bidir.dsval.to_s
            # puts "BIDIR-IBE #{@ibe}"
          else
            @ibe = @function_output.dsval.to_s
            # puts "OUTPUT-IBE #{@ibe}"
          end
          if @ibe == '1'
            @obe = '0'
          else
            @obe = '1'
          end
          # puts "IBE <#{@ibe}> OBE <#{@obe}>"
        end
      end
    end

    def commit_port_state
      unless @function_control.nil?
        get_ibe_obe
        if @state == IN0 || @state == IN1 || @state == IN0_OUT1 || @state == IN1_OUT0
          _control_state = @ibe
        else
          _control_state = @obe
        end
        if @function_control.access_cnt != 0 && @function_control.state != _control_state
          fail 'multiple port accessed control with different OBE'
        end
        @function_control.access_cnt = @function_control.access_cnt + 1
        @function_control.state = _control_state
      end
      if @state == IN1 || @state == OUT1
        update_function_state('1', '1')
      elsif @state == IN0_OUT1 || @state == OUT1_IN0
        update_function_state('0', '1')
      elsif @state == IN1_OUT0 || @state == OUT0_IN1
        update_function_state('1', '0')
      else # @state == IN0 || @state == OUT0
        update_function_state('0', '0')
      end
    end
  end # class BSDLport

  class BSDLfile
    attr_reader :size_reg_ir, :size_reg_dr_bsdl, :ir_opcode2bits, :ir_bits2opcode, :ir_capture, :reg_idcode, :bsdlcells_description, :bsdlcells_state, :bsdlportnames, :bsdlport2cells, :pinname_downcase, :pinname_upcase

    def initialize(_bsdl_filename, _pinname_downcase, _pinname_upcase)
      @ir_opcode2bits        = {}
      @ir_bits2opcode        = {}

      @ir_capture            = ''

      @reg_idcode            = []

      @size_reg_ir           = 0
      @size_reg_dr_bsdl      = 0

      @bsdlcells             = []
      @bsdlportnames         = []
      @bsdlport2cells        = {}
      @bsdldiffnames         = []

      @bsdlcells_description = []
      @bsdlcells_state       = []

      @pinname_downcase      = _pinname_downcase
      @pinname_upcase        = _pinname_upcase

      read_bsdl_file(_bsdl_filename)
    end # initialize

    def read_bsdl_file(_bsdl_filename)
      ir_start   = false
      dr_start   = false
      diff_start = false
      _diff_h = {}

      # bsdl_file = File.dirname(File.expand_path(__FILE__)) + '/t_ip_bsdl.bsdl'
      ifile = File.open(_bsdl_filename, 'r')
      while iline = ifile.gets
        # iline.upcase!
        i1_a = iline.split('--')
        i2_a = i1_a[0].split
        if i2_a.size != 0
          # puts "SIZE #{i2_a.size}: #{i2_a.join(" ")}"
          if i2_a[0] == 'ATTRIBUTE' || i2_a[0] == 'attribute'
            case i2_a[1]
                 when 'INSTRUCTION_LENGTH'
                   @size_reg_ir = get_numberic(i2_a).to_i
                 when 'INSTRUCTION_OPCODE'
                   ir_start = true
                 when 'INSTRUCTION_CAPTURE'
                   @ir_capture = get_numberic(i2_a)
                 when 'BOUNDARY_LENGTH'
                   @size_reg_dr_bsdl = get_numberic(i2_a).to_i
                 when 'BOUNDARY_REGISTER'
                   dr_start = true
                 when 'PORT_GROUPING'
                   if ifile.gets =~ /DIFFERENTIAL_VOLTAGE/
                     diff_start = true
                   end
                 when 'IDCODE_REGISTER'
                   while iline = ifile.gets
                     _d1_a = iline.split("\"")
                     @reg_idcode = @reg_idcode + _d1_a[1].split('')
                     break if iline =~ /;/
                   end
                   @reg_idcode.reverse!
              end

          elsif i2_a[0] =~ /^"/
            if ir_start
              _info_a = get_info(i1_a[0])
              @ir_opcode2bits[_info_a[0].to_s] = _info_a[1].to_s
              @ir_bits2opcode[_info_a[1].to_s] = _info_a[0].to_s
              # puts "IR_START #{_info_a[0].to_s} #{_info_a[1].to_s} #{i2_a.join(" ")}"
            elsif dr_start
              # puts "DR_START #{i2_a.join(" ")}"
              _info_a = get_info(i1_a[0])
              if @pinname_downcase
                _info_a[2].downcase!
              end
              if @pinname_upcase
                _info_a[2].upcase!
              end
              @bsdlcells << BSDLcell.new(_info_a)
              @bsdlcells_description << @bsdlcells.last.description
              @bsdlcells_state << @bsdlcells.last.state.to_s
            elsif diff_start
              _info_a = get_info(i1_a[0])
              if @pinname_downcase
                _info_a[1].downcase!
                _info_a[2].downcase!
              end
              if @pinname_upcase
                _info_a[1].upcase!
                _info_a[2].upcase!
              end
              _diff_h[_info_a[1].to_s] = _info_a[2].to_s
            end
            if i2_a.last =~ /;/
              ir_start   = false
              dr_start   = false
              diff_start = false
            end
          end
        end
      end
      ifile.close

      @bsdlcells.each do |_cell|
        _portname = _cell.port.to_s
        if _portname != '*'
          unless @bsdlportnames.include?(_portname)
            @bsdlportnames << _portname.to_s
            @bsdlport2cells[_portname] = BSDLport.new
          end
          if _cell.function =~ /(INPUT|input)/
            @bsdlport2cells[_portname].function_input = _cell
          elsif _cell.function =~ /(OUTPUT|output)/
            @bsdlport2cells[_portname].function_output = _cell
            @bsdlport2cells[_portname].function_control = @bsdlcells[_cell.ccell]
          elsif _cell.function =~ /(BIDIR|bidir)/
            @bsdlport2cells[_portname].function_bidir = _cell
            @bsdlport2cells[_portname].function_control = @bsdlcells[_cell.ccell]
          end
        end
      end

      _diff_h.each_pair do |_p1, _p2|
        if @bsdlportnames.include?(_p1)
          @bsdlport2cells[_p1].diffport = _p2
          @bsdldiffnames << _p2.to_s
        else
          @bsdlport2cells[_p2].diffport = _p1
          @bsdldiffnames << _p1.to_s
        end
      end

      # @bsdlcells.each do |_cell|
      #   puts _cell.info
      # end

      # @bsdlportnames.each do |_portname|
      #   puts _portname
      #   puts @bsdlport2cells[_portname].info
      # end
    end # read_bsdl_file

    def get_numberic(_i_a)
      _i_a.pop until _i_a.last =~ /\d/
      _i_a.last.delete(";\"")
    end # getSize

    def get_info(_info)
      _i_a = _info.split(')')
      _i_a[0].delete!("\"\s\t")
      _i_a[0].sub!('(', ',')
      _i_a[0].split(',')
    end # get_info

    def float_bsdl_pins
      (@bsdlportnames + @bsdldiffnames).each do |_portname|
        $dut.pin(_portname).dont_care
      end
    end

    def get_port_array(_ports)
      if _ports.size == 0
        _port_a = @bsdlportnames
      else
        # begin
        #   $dut.pins(_ports).map(& :id)
        # rescue
        #   _port_a = [_ports]
        # else
        #   _port_a = $dut.pins(_ports).map(& :id) # please note this returns an address to id
        # end
        if @bsdlportnames.include?(_ports)
          _port_a = [_ports]
        else
          # puts "MAP port #{_ports}"
          _port_a = $dut.pins(_ports).map(& :id) # please note this returns an address to id
        end
      end
      # puts _port_a.join(",")
      _port_a
    end

    def update_bsdl_port_state(_state, _ports)
      _port_a = get_port_array(_ports)
      _port_a.each do |_portname|
        _portname = _portname.to_s # convert address to actual text
        if @bsdlport2cells.key?(_portname)
          @bsdlport2cells[_portname].state = _state
        else
          puts '*************'
          puts '*** ERROR '
          puts "*** <#{_portname}> does not recognize as part of bsdl pin list"
          puts '*** please use the options in sub_blocks.rb to try to match bsdl pinnames to pins.rb names in sim'
          puts '***    :bsdl_pinname_downcase true'
          puts '***    :bsdl_pinname_upcase   true'
          fail '*************'
        end
      end
    end

    def force_tdo_compare_control(_compare, _ports)
      _port_a = get_port_array(_ports)
      _port_a.each do |_portname|
        _portname = _portname.to_s # convert address to actual text
        unless @bsdlport2cells[_portname].function_control.nil?
          @bsdlport2cells[_portname].function_control.compare = _compare.to_s
        end
      end
    end

    def force_tdo_compare_output(_compare, _ports)
      _port_a = get_port_array(_ports)
      _port_a.each do |_portname|
        _portname = _portname.to_s # convert address to actual text
        unless @bsdlport2cells[_portname].function_output.nil?
          @bsdlport2cells[_portname].function_output.compare = _compare.to_s
        end
      end
    end

    def commit_bsdl_port_state
      @bsdlcells.each do |_cell|
        _cell.access_cnt = 0
      end
      @bsdlport2cells.each_pair do |_portname, _bsdlport|
        # puts _portname
        # puts _bsdlport.info
        _bsdlport.commit_port_state
        # puts _bsdlport.info
      end
      0.upto(@size_reg_dr_bsdl - 1) do |_i|
        @bsdlcells_state[_i] = @bsdlcells[_i].state.to_s
      end
      puts 'BSDL IN'
      puts @bsdlcells_state.join
    end

    def load_bsdl_port_state(_reg_dr, _in0, _in1, _out0, _out1)
      _in0.clear
      _in1.clear
      _out0.clear
      _out1.clear
      @bsdlport2cells.each_pair do |_portname, _bsdlport|
        if _bsdlport.state == IN0 || _bsdlport.state == IN0_OUT1
          _in0 << _portname.to_s
          unless _bsdlport.diffport.nil?
            _in1 << _bsdlport.diffport.to_s
          end
        elsif _bsdlport.state == IN1 || _bsdlport.state == IN1_OUT0
          _in1 << _portname.to_s
          unless _bsdlport.diffport.nil?
            _in0 << _bsdlport.diffport.to_s
          end
        elsif _bsdlport.state == OUT0 || _bsdlport.state == OUT0_IN1
          _out0 << _portname.to_s
          unless _bsdlport.diffport.nil?
            _out1 << _bsdlport.diffport.to_s
          end
        elsif _bsdlport.state == OUT1 || _bsdlport.state == OUT1_IN0
          _out1 << _portname.to_s
          unless _bsdlport.diffport.nil?
            _out0 << _bsdlport.diffport.to_s
          end
        end
      end
      0.upto(@size_reg_dr_bsdl - 1) do |_i|
        if @bsdlcells[_i].compare.nil?
          _reg_dr[_i] = @bsdlcells[_i].state.to_s
        else
          _reg_dr[_i] = @bsdlcells[_i].compare.to_s
        end
      end
      puts 'BSDL OUT'
      puts _reg_dr.join
    end
  end # class BSDLchain

  class BSDL
    include Origen::Model
    # include RosettaStone #import regs map

    TLR = 0
    RTI = 1
    DR_SELECT = 2
    DR_CAPTURE = 3
    DR_SHIFT = 4
    DR_EXIT1 = 5
    DR_PAUSE = 6
    DR_EXIT2 = 7
    DR_UPDATE = 8
    IR_SELECT = 9
    IR_CAPTURE = 10
    IR_SHIFT = 11
    IR_EXIT1 = 12
    IR_PAUSE = 13
    IR_EXIT2 = 14
    IR_UPDATE = 15

    def initialize(options = {})
      options = {
        bsdl_filename:         "#{Origen.app.root}/t_ip_bsdl.bsdl",
        bsdl_pinname_downcase: false,
        bsdl_pinname_upcase:   false
      }.merge(options)

      @jtag_state_a = Array[
                   'TLR',
                   'RTI',
                   'DR_SELECT',
                   'DR_CAPTURE',
                   'DR_SHIFT',
                   'DR_EXIT1',
                   'DR_PAUSE',
                   'DR_EXIT2',
                   'DR_UPDATE',
                   'IR_SELECT',
                   'IR_CAPTURE',
                   'IR_SHIFT',
                   'IR_EXIT1',
                   'IR_PAUSE',
                   'IR_EXIT2',
                   'IR_UPDATE'
                   ]
      @jtag_state = TLR

      @bsdlfile = BSDLfile.new(options[:bsdl_filename], options[:bsdl_pinname_downcase], options[:bsdl_pinname_upcase])

      @reg_ir = Array.new(@bsdlfile.size_reg_ir, 'X')
      @reg_dr_bsdl = Array.new(@bsdlfile.size_reg_dr_bsdl, 'X')
      @reg_dr = []

      @in0  = []
      @in1  = []
      @out0 = []
      @out1 = []

      @ir_state = ''

      @shift_ctr = 0

      if defined?(custom_init)
        custom_init
      end
    end

    def jtag_shift(_tms, _tdi)
      _tms_a = _tms.split('')
      _tdi_a = _tdi.split('')

      0.upto(_tms_a.size - 1) do |i|
        update_jtag_state(_tms_a[i], _tdi_a[i])
      end
    end

    def float_bsdl_pins
      @bsdlfile.float_bsdl_pins
    end

    def update_jtag_state(_tms, _tdi)
      pin(:tms).drive(_tms.to_i)
      pin(:tdi).drive(_tdi.to_i)

      _tdo = 'X'
      if @jtag_state == IR_SHIFT
        @reg_ir.push(_tdi)
        _tdo = @reg_ir.shift
      elsif @jtag_state == DR_SHIFT
        @reg_dr.push(_tdi)
        _tdo = @reg_dr.shift
      end
      if _tdo.to_s =~ /(X|x|Z|z)/
        pin(:tdo).dont_care
      else
        pin(:tdo).assert(_tdo.to_i)
      end

      case @jtag_state
        when TLR
          @jtag_state = (_tms == '0') ? RTI : TLR;
        when RTI
          @jtag_state = (_tms == '0') ? RTI : DR_SELECT;
        when DR_SELECT
          @jtag_state = (_tms == '0') ? DR_CAPTURE : IR_SELECT;
        when DR_CAPTURE
          @jtag_state = (_tms == '0') ? DR_SHIFT : DR_EXIT1;
        when DR_SHIFT
          @jtag_state = (_tms == '0') ? DR_SHIFT : DR_EXIT1;
        when DR_EXIT1
          @jtag_state = (_tms == '0') ? DR_PAUSE : DR_UPDATE;
        when DR_PAUSE
          @jtag_state = (_tms == '0') ? DR_PAUSE : DR_EXIT2;
        when DR_EXIT2
          @jtag_state = (_tms == '0') ? DR_SHIFT : DR_UPDATE;
        when DR_UPDATE
          @jtag_state = (_tms == '0') ? RTI : DR_SELECT;
        when IR_SELECT
          @jtag_state = (_tms == '0') ? IR_CAPTURE : TLR;
        when IR_CAPTURE
          @jtag_state = (_tms == '0') ? IR_SHIFT : IR_EXIT1;
        when IR_SHIFT
          @jtag_state = (_tms == '0') ? IR_SHIFT : IR_EXIT1;
        when IR_EXIT1
          @jtag_state = (_tms == '0') ? IR_PAUSE : IR_UPDATE;
        when IR_PAUSE
          @jtag_state = (_tms == '0') ? IR_PAUSE : IR_EXIT2;
        when IR_EXIT2
          @jtag_state = (_tms == '0') ? IR_SHIFT : IR_UPDATE;
        when IR_UPDATE
          @jtag_state = (_tms == '0') ? RTI : DR_SELECT;
      end

      $tester.cycle(repeat: 1)

      _comment = "#{@jtag_state_a[@jtag_state]}"

      if @ir_state =~ /EXTEST/
        # compare at OUTPUT pins
        if @jtag_state == DR_EXIT1
          @out0.each do |_port|
            pin(_port).assert(0)
          end
          @out1.each do |_port|
            pin(_port).assert(1)
          end
        end
        if @jtag_state == DR_EXIT2
          float_bsdl_pins
        end
        # bsdlChain completely shifted into reg_dr
        if @jtag_state == DR_UPDATE || @jtag_state == IR_UPDATE
          @bsdlfile.load_bsdl_port_state(@reg_dr, @in0, @in1, @out0, @out1)
          # release drives and compares
          float_bsdl_pins
          if @in0.size > 0
            puts "IN0  <#{@in0.size}>\n#{@in0.join(',')}"
          end
          if @in1.size > 0
            puts "IN1  <#{@in1.size}>\n#{@in1.join(',')}"
          end
          if @out0.size > 0
            puts "OUT0 <#{@out0.size}>\n#{@out0.join(',')}"
          end
          if @out1.size > 0
            puts "OUT1 <#{@out1.size}>\n#{@out1.join(',')}"
          end
        end
        # drive opposite states at INPUT pins
        if @jtag_state == DR_SELECT || @jtag_state == DR_SHIFT
          @in0.each do |_port|
            pin(_port).drive(1)
          end
          @in1.each do |_port|
            pin(_port).drive(0)
          end
        end
        # drive correct states at INPUT pins
        if @jtag_state == DR_CAPTURE
          @in0.each do |_port|
            pin(_port).drive(0)
          end
          @in1.each do |_port|
            pin(_port).drive(1)
          end
        end
        # track bsdl tdi/tdo pin correlation
        if @jtag_state == DR_SHIFT
          # TDI
          if @shift_ctr - 5 >= 0
            _comment.concat(": #{@shift_ctr - 5} bsdl_tdi #{@bsdlfile.bsdlcells_description[@shift_ctr - 5]}")
          end
          # TDO
          if @ir_state =~ /EXTEST/ && @shift_ctr < @reg_dr.size
            _comment.concat(": #{@shift_ctr} bsdl_tdo #{@bsdlfile.bsdlcells_description[@shift_ctr]}")
          end
        end

      elsif @ir_state =~ /PRELOAD/
        if @jtag_state == DR_SHIFT
          # TDI
          if @shift_ctr - 5 >= 0
            _comment.concat(": #{@shift_ctr - 5} bsdl_tdi #{@bsdlfile.bsdlcells_description[@shift_ctr - 5]}")
          end
        end

      elsif @jtag_state == IR_SHIFT || @jtag_state == DR_SHIFT
        _comment.concat(": #{@shift_ctr}")
      end

      if @jtag_state == IR_SHIFT || @jtag_state == DR_SHIFT
        @shift_ctr = @shift_ctr + 1
      end

      if @jtag_state == IR_EXIT1
        _ir_bits = @reg_ir.reverse.join
        _comment.concat(": #{_ir_bits} #{@bsdlfile.ir_bits2opcode[_ir_bits]}")
      end

      cc "#{_comment}"
    end

    def jtag_setup_rti
      pin(:tms).drive(1)
      pin(:tdi).drive(0)
      pin(:tdo).dont_care
      $tester.cycle(repeat: 4)
      jtag_shift('10', '00') # ends with RTI
    end # jtag_setup_rti: PATTERN_OPTION

    def jtag_ir_opcode(_ir_opcode)
      @shift_ctr = 0
      unless @bsdlfile.ir_opcode2bits.key?(_ir_opcode)
        puts "ERROR: IROPCODE not available #{_ir_opcode}"
      end
      if @bsdlfile.ir_capture != ''
        @reg_ir = @bsdlfile.ir_capture.reverse.split('')
      end
      jtag_shift('110000000', '000011001')
      jtag_shift((('0' * (@reg_ir.size - 1)) + '1'), @bsdlfile.ir_opcode2bits[_ir_opcode].reverse)
      @ir_state = _ir_opcode
      jtag_shift('011000', '000000') # ends with RTI
      puts "IR_OPCODE #{@ir_state}"
    end # jtag_ir_opcode: PATTERN_OPTION

    def jtag_dr_id
      @reg_dr = []
      @bsdlfile.reg_idcode.each do |_i|
        @reg_dr << _i.to_s
      end
      puts "IDCODE #{@reg_dr.size} #{@reg_dr.join}"
      @shift_ctr = 0
      jtag_shift('10000000', '00011001')
      jtag_shift((('0' * (@bsdlfile.reg_idcode.size - 1)) + '1'), ('0' * @bsdlfile.reg_idcode.size))
      jtag_shift('011000', '000000')  # ends with RTI
    end

    def jtag_dr_bsdl
      @reg_dr = @reg_dr_bsdl
      @shift_ctr = 0
      jtag_shift('10000000', '00011001')
      puts '**********'
      @bsdlfile.commit_bsdl_port_state
      jtag_shift((('0' * (@reg_dr_bsdl.size - 1)) + '1'), @bsdlfile.bsdlcells_state.join)
      jtag_shift('011000', '000000')  # ends with RTI
    end # jtag_dr_bsdl: PATTERN_OPTION

    def update_bsdl_input0(_port_a = '')
      @bsdlfile.update_bsdl_port_state(IN0, _port_a)
    end

    def update_bsdl_input1(_port_a = '')
      @bsdlfile.update_bsdl_port_state(IN1, _port_a)
    end

    def update_bsdl_output0(_port_a = '')
      @bsdlfile.update_bsdl_port_state(OUT0, _port_a)
    end

    def update_bsdl_output1(_port_a = '')
      @bsdlfile.update_bsdl_port_state(OUT1, _port_a)
    end

    def update_bsdl_input0_o1(_port_a = '')
      @bsdlfile.update_bsdl_port_state(IN0_OUT1, _port_a)
    end

    def update_bsdl_input1_o0(_port_a = '')
      @bsdlfile.update_bsdl_port_state(IN1_OUT0, _port_a)
    end

    def update_bsdl_output0_i1(_port_a = '')
      @bsdlfile.update_bsdl_port_state(OUT0_IN1, _port_a)
    end

    def update_bsdl_output1_i0(_port_a = '')
      @bsdlfile.update_bsdl_port_state(OUT1_IN0, _port_a)
    end

    def force_tdo_compare_control(_compare, _port_a = '')
      @bsdlfile.force_tdo_compare_control(_compare, _port_a)
    end

    def force_tdo_compare_output(_compare, _port_a = '')
      @bsdlfile.force_tdo_compare_output(_compare, _port_a)
    end

    def get_bsdl_pins
      @bsdlfile.bsdlportnames
    end
  end # class BSDL
end # module BsdlOrigen
