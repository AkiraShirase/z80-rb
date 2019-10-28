# -*- coding: BINARY -*-
module Z80
	##
	#  Adds the TAP format support to your *program*.
	#
	#  Example:
	#
	#      puts Z80::TAP.parse_file("examples/calculator.tap").to_a
	#
	#      Program: "calculator" LINE 10 (226/226)
  #      Bytes: "calculator" CODE 32768,61
	#
	#      # convert a TZX file to a TAP file (may not work for custom loaders)
	#      Z80::TAP.parse_file('foobar.tzx') {|t| t.save_tap('foobar', append:true) }
	#
	#  Program.import_file will make use of Z80::TAP.read_data.
	#  Pass additional +:index+ => +n+ argument to Program.import_file to choose n'th chunk from a tap file.
	#
	#      import_file 'somefile.tap', :index => 2
	#
	#  You may
	#    include Z80::TAP
	#  in your Z80 *Program* class and instances of it will be enriched by the three additional methods:
	#
	#  * #save_tap
	#  * #to_tap
	#  * #to_tap_chunk
	#
	#  In fact this mixin may be used on any class as long as either:
	#
	#  * Your class have +code+ and +org+ attributes producing a binary string and a starting address of a program.
	#  * Your class provides your own implementation of #to_tap_chunk.
	#
	#  The method #to_tap_chunk may be overridden to create other TAP file types.
	#  The default implementation creates a TYPE_CODE file based on +code+ and +org+ properties
	#  of the base class.
	#  The custom implementation may use one of the:
	#  TAP::HeaderBody.new_code, TAP::HeaderBody.new_program, TAP::HeaderBody.new_var_array
	#  helper methods to construct a proper TAP::HeaderBody instance.
	#
	#  =====See:
	#  https://faqwiki.zxnet.co.uk/wiki/TAP_format
	#
	#            |------ Spectrum-generated data -------|       |---------|
	#      13 00 00 03 52 4f 4d 7x20 02 00 00 00 00 80 f1 04 00 ff f3 af a3
	#      ^^^^^...... first block is 19 bytes (17 bytes+flag+checksum)
	#            ^^... flag byte (A reg, 00 for headers, ff for data blocks)
	#               ^^ first byte of header, indicating a code block
	#      file name ..^^^^^^^^^^^^^
	#      header info ..............^^^^^^^^^^^^^^^^^
	#      checksum of header .........................^^
	#      length of second block ........................^^^^^
	#      flag byte ...........................................^^
	#      first two bytes of rom .................................^^^^^
	#      checksum (checkbittoggle would be a better name!).............^^
	#
	module TAP
		class TapeError < StandardError; end
		TYPE_PROGRAM      = 0
		TYPE_NUMBER_ARRAY = 1
		TYPE_CHAR_ARRAY   = 2
		TYPE_CODE         = 3
		##
		#  Saves self in a TAP file.
		#
		#  The tap data is being generated by #to_tap_chunk.
		#
		#  +filename+ specifies the file name to save to. The ".tap" extension may be omitted.
		#
		#  =====Options:
		#
		#  * +:name+ should contain max 10 ascii characters.
		#    If not given, the base name of a +filename+ will be used instead.
		#  * +:append+ if +true+ the data will be appended to the file.
		#    Otherwise the file is being truncated.
		#
		#  Any additional option will be passed to the #to_tap_chunk method.
		def save_tap(filename, append:false, name:nil, **opts)
			name = File.basename(filename, '.tap') unless name
			to_tap_chunk(name, **opts).save_tap filename, append:append
		end
		##
		#  Produces a TAP blob as a binary string from self.
		#
		#  A sugar for calling TAP::HeaderBody#to_tap method on the result produced by #to_tap_chunk.
		#
		#  +name+ should contain max 10 ascii characters.
		#  Any options given will be passed to the #to_tap_chunk method.
		def to_tap(name, **opts)
			to_tap_chunk(name, **opts).to_tap
		end
		##
		#  Creates a TAP::HeaderBody chunk from self.
		#
    #  By default it uses Z80#code and the Z80#org to produce the tap data.
    #
		#  This method is used by #to_tap and #save_tap.
		#
		#  +name+ should contain max 10 ascii characters.
		#  Optionally +org+ may be given to override the starting code address.
		def to_tap_chunk(name, org:nil)
			HeaderBody.new_code(name, code, org||self.org)
		end

		##
		#  A class that represents the optional header and the single body chunk of a TAP file.
		#
		#  Instances of this class are produced by methods such as: TAP#to_tap_chunk or TAP.parse_file.
		#
		#  Properties:
		#
		#  * +header+ as a Z80::TAP::Header instance or +nil+
		#  * +body+ as a ::Z80::TAP::Body instance
		#
		#  HeaderBody#to_tap produces a TAP blob as a binary string.
		class HeaderBody
			attr_reader :header, :body
			def initialize(header, body)
				@header = header
				@body = body
			end
			##
			#  For humans.
			def to_s
				if header.nil?
					"Bytes: ?????????? (#{body.data.bytesize})"
				else
					header.to_s
				end
			end
			##
			#  Saves this chunk as a TAP file.
			#
			#  +filename+ specifies the file name to save to. The ".tap" extension may be omitted.
			#
			#  If +:append+ is +true+ the data will be appended to the file.
			#  Otherwise the file is being truncated.
			def save_tap(filename, append:false)
				filename+= '.tap' unless File.extname(filename).downcase == '.tap'
				File.open(filename, append ? 'ab' : 'wb') {|f| f.write to_tap }
			end
			##
			#  Produces a TAP blob as a binary string from this chunk.
			def to_tap
				res = ''
				res << header.to_tap unless header.nil?
				res << body.to_tap(header && header.length) unless body.nil? 
				res
			end
			##
			#  +true+ if this chunk represents a number or character array
			def array?
				header && header.array?
			end
			##
			#  +true+ if this chunk represents a basic program
			def program?
				header && header.program?
			end
			##
			#  +true+ if this chunk represents a code
			def code?
				header && header.code?
			end
			##
			#  +true+ if this chunk represents a screen data
			def screen?
				header && header.screen?
			end
			class << self
				##
				#  Creates a HeaderBody of the type +TYPE_CODE+.
				#
				#  * +name+ should contain max 10 ascii characters.
				#  * +code+ should be a binary string.
				#  * +org+ should be an integer indicating the starting address of the code.
				def new_code(name, code, org)
					HeaderBody.new(
						Header.new(TYPE_CODE, name, code.bytesize, org, 0x8000),
						Body.new(code)
					)
				end
				##
				#  Creates a HeaderBody of the type +TYPE_PROGRAM+.
				#
				#  * +name+ should contain max 10 ascii characters.
				#  * +code+ should be a binary string representing ZX Spectrum's program and variables.
				#  * optional +line+ should be an integer indicating the starting line of the program.
				#  * optional +prog_length+ should be an integer indicating the length (in bytes) of the program.
				def new_program(name, code, line:nil, prog_length:nil)
					HeaderBody.new(
						Header.new(TYPE_PROGRAM, name, code.bytesize, line || 32768, prog_length || code.bytesize),
						Body.new(code)
					)
				end
				##
				#  Creates a HeaderBody of the type +TYPE_NUMBER_ARRAY+ or +TYPE_CHAR_ARRAY+.
				#
				#  * +name+ should contain max 10 ascii characters.
				#  * +code+ should be a binary string representing ZX Spectrum's array variable body.
				#  * +head+ should be the header octet of the variable data.
				#    Based on this number the appropriate type of the tap file is being chosen.
				def new_var_array(name, code, head)
					type = case head & 0b11100000
					when 0b10000000
						TYPE_NUMBER_ARRAY
					when 0b11000000
						TYPE_CHAR_ARRAY
					else
						raise TapeError, "can't guess TAP type from a variable head"
					end
					p1 = (head & 0xff) << 8
					HeaderBody.new(
						Header.new(type, name, code.bytesize, p1, 0x8000),
						Body.new(code)
					)
				end
			end
		end # HeaderBody
		##
		#  A struct which represents the header chunk of a TAP file.
		#
		#  Header struct properties:
		#
		#  * +type+ - 0 - program, 1 - number array, 2 - character array, 3 - code.
		#  * +name+ as a string.
		#  * +length+ the expected bytesize of the following body chunk as an integer.
		#  * +p1+ as an integer.
		#  * +p2+ as an integer.
		#
		#  For a program:
		#
		#  * +line+ returns the starting line of a program.
		#  * +prog_length+ returns the length in bytes of the program itself.
		#  * +vars_length+ returns the length in bytes of the variables data.
		#
		#  For a number or character array:
		#
		#  * +array_name+ returns the original variable name.
		#  * +array_head+ returns the header octet of the original variable.
		#
		#  For a code:
		#
		#  * +address+, +addr+ and +org+ returns the original code address.
		#
		#
		Header = ::Struct.new :type, :name, :length, :p1, :p2 do
			def to_s
				case type
				when TYPE_PROGRAM
					"Program: #{name.inspect} LINE #{p1} (#{p2}/#{length})"
				when TYPE_CODE
					"Bytes: #{name.inspect} CODE #{p1},#{length}"
				when TYPE_CHAR_ARRAY
					"Character array: #{name.inspect} DATA #{array_name}$()"
				when TYPE_NUMBER_ARRAY
					"Number array: #{name.inspect} DATA #{array_name}()"
				else
					"Unknown: #{name.inspect}"
				end
			end
			def address
				p1 if code?
			end
			alias_method :addr, :address
			alias_method :org, :address
			def line
				p1 if program?
			end
			def prog_length
				p2 if program?
			end
			def vars_length
				if program?
					length - p1
				end
			end
			def array_head
				if array?
					(p1 >> 8) & 0b11111111
				end
			end
			def array_name
				if array?
					((array_head & 0b01111111)|0b01100000).chr
				end
			end
			def array?
				type == TYPE_CHAR_ARRAY || type == TYPE_NUMBER_ARRAY
			end
			def program?
				type == TYPE_PROGRAM
			end
			def code?
				type == TYPE_CODE
			end
			def screen?
				code? and length == 6912 and p1 == 16384
			end
			def to_tap
				unless name.ascii_only?
					$stderr.puts "WARNING: TAP name should cointain only ASCII (7-bit) characters!"
					name.force_encoding Encoding::BINARY
				end
				head = [0, type].pack('CC') + name.byteslice(0,10).ljust(10) + [length, p1, p2].pack('v3')
				TAP.addsum head
				[head.bytesize].pack('v') + head
			end
		end

		##
		#  A struct which represents the body chunk of a TAP file.
		#  Property +data+ is a binary string containing the body data.
		Body = ::Struct.new :data do
			def to_tap(length=nil)
				raise TapeError, "Header length dosn't match" unless length.nil? || data.bytesize == length
				body = "\xff" + data
				TAP.addsum body
				[body.bytesize].pack('v') + body
			end
		end

		##
		#  TAP tools
		#
		class << self
			def addsum(s) # :nodoc:
				s << s.bytes.inject(&:^).chr
			end
			def cksum(s) # :nodoc:
				s.bytes.inject(&:^).zero?
			end

			##
			#  Reads a data chunk from a TAP file. Returns a binary string.
			#
			#  Program.import_file uses this method to read from a TAP file.
			#
			#  See read_chunk for +opts+.
			def read_data(filename, **opts)
				TAP.read_chunk(filename, **opts) do |chunk|
					if chunk.header
						$stderr.puts "Importing: `#{filename}': (#{chunk.header.name})"
					else
						$stderr.puts "Importing: `#{filename}': headerless chunk"
					end
					return chunk.body.data
				end
				raise "Chunk: #{index} not found in a TAP file: `#{filename}`"
			end

			##
			#  Reads a TAP::HeaderBody chunk from a TAP file.
			#
			#  Pass additional +:name+ argument to search for the header name
			#  or a +:index+ => +n+ argument to choose the n'th chunk (1-based) from a file.
			#
			#  Pass a block to visit a chunk.
			#
			def read_chunk(filename, name:nil, index:nil)
				parser = parse_file(filename)
				chunk, = if name.nil?
					index = 1 if index.nil?
					parser.each.with_index(1).find { |chunk, i| i == index }
				else
					parser.find { |chunk| name === chunk.header.name }
				end
				return unless chunk
				if block_given?
					yield chunk
				else
					chunk
				end
			end

			##
			#  Returns an Enumerator of TAP::HeaderBody chunks representing segments of a TAP +file+.
			#  Optionally unwraps TZX headers.
			#
			#  Pass a +block+ to visit each +chunk+.
			def parse_file(filename, &block)
				tap = File.open(filename, 'rb') {|f| f.read }
				TAP.parse_tap(tap, filename, &block)
			end

			##
			#  Returns an Enumerator of TAP::HeaderBody chunks representing segments of a TAP blob.
			#  Optionally unwraps TZX headers.
			#
			#  The +tap+ argument must be a binary string.
			#  Pass a +block+ to visit each +chunk+.
			#  Optionally pass a +file+ name for error messages.
			def parse_tap(tap, file='-', &block)
				tap, is_tzx = TAP.unpack_from_tzx_header tap, file
				enu = ::Enumerator.new do |y|
					header = nil
					loop do
						if is_tzx
							tap = TAP.unpack_from_tzx_chunk tap, file
						end
						size, tap = tap.unpack('va*')
						break if size.nil? && tap.empty?
						chunk, tap = tap.unpack("a#{size}a*")
						raise TapeError, "Invalid TAP file checksum: `#{file}'." unless cksum(chunk)
						raise TapeError, "TAP block too short: `#{file}'." unless chunk.bytesize == size
						type, data, _cksum = chunk.unpack("Ca#{size-2}C")
						case type
						when 0x00
							raise TapeError, "Invalid TAP header length: `#{file}'." unless data.bytesize == 17
							header = Header.new(*data.unpack('CA10v3'))
						when 0xff
							unless header.nil?
								raise TapeError, "TAP bytes length doesn't match length in header: `#{file}'." unless data.bytesize == header.length
							end
							chunk = HeaderBody.new header, Body.new(data)
							header = nil
							y << chunk
						else
							raise TapeError, "Invalid TAP file chunk: `#{file}'."
						end
					end
				end
				if block_given?
					enu.each(&block)
				else
					enu
				end
			end

			def unpack_from_tzx_header(tap, file='-') # :nodoc:
				if tap.start_with?("ZXTape!\x1A") && tap.bytesize > 13
					_signature, major, _minor, tap = tap.unpack("a8CCa*")
					# $stderr.puts "unpacking TZX header: #{major}.#{_minor}"
					raise "Unknown TZX major: `#{file}'" unless major == 1
					[tap, true]
				else
					[tap, false]
				end
			end

			def unpack_from_tzx_chunk(tap, file='-') # :nodoc:
				if tap.bytesize > 3
					id, tap = tap.unpack("Ca*")
					# $stderr.puts "unpacking TZX: id=0x#{id.to_s(16)}"
					case id
					when 0x10
						_wait, tap = tap.unpack("va*")
					when 0x35
						_name, size, tap = tap.unpack("a10L<a*")
						_info, tap = tap.unpack("a#{size}a*")
					when 0x5A
						_glue, tap = tap.unpack("a9a*")
					else
						raise "Only the standard speed data block are currently handled in TZX files, got: 0x#{id.to_s(16)} in `#{file}'"
					end
				end
				tap
			end
		end
	end
	unless const_defined?(:TZX)
		# :nodoc:
		TZX = TAP
	end
end
