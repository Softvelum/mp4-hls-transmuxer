#
# Provided by WMSPanel team - https://wmspanel.com/
# Author: Alex Pokotilo
# Contact: support@wmspanel.com
#

# ISOBASE FF -> MPEG2TS converter

class IsoBaseMediaFile
  class InvalidFileException < Exception
  end

  class Box
    attr_accessor :file, :offset, :size, :type, :parent

    def getInt8
      buffer =  (@file.read 1).unpack('C*')
      raise InvalidFileException if buffer.length != 1
      @offset+=1
      return  buffer[0]
    end

    def getInt16
      buffer =  (@file.read 2).unpack('C*')
      raise InvalidFileException if buffer.length != 2
      @offset+=2
      return  0x100 * buffer[0] + buffer[1]
    end

    def getInt24
      buffer =  (@file.read 3).unpack('C*')
      raise InvalidFileException if buffer.length != 3
      @offset+=3
      return  0x10000  * buffer[0] + 0x100 * buffer[1] + buffer[2]
    end

    def getInt32
      buffer =  (@file.read 4).unpack('C*')
      raise InvalidFileException if buffer.length != 4
      @offset+=4
      return  0x1000000 * buffer[0] + 0x10000  * buffer[1] + 0x100 * buffer[2] + buffer[3]
    end

    def getInt64
      return (getInt32() << 32) + getInt32()
    end

    def getInt32Array n
      result = []
      n.times do
        result << getInt32
      end
      result
    end

    def get32BitString
      buffer = @file.read 4
      raise InvalidFileException if buffer.length != 4
      @offset+=4
      return buffer
    end
    def getFixedSizeString n
      len = (@file.read 1).unpack('C*')
      raise InvalidFileException if len.length != 1
      len = len[0]
      raise InvalidFileException if len > n - 1

      buffer = (len > 0) ? @file.read(len) : nil
      if len + 1 < 32
        @file.seek(32 - (len + 1) , IO::SEEK_CUR)
      end
      @offset+= n
      return buffer
    end

    def getByteArray n
      buffer =  (@file.read n).unpack('C*')
      raise InvalidFileException if buffer.length != n
      @offset+=n
      return buffer
    end


    def skipNBytes bytes2skip
      if @size > @offset + bytes2skip
        @file.seek(bytes2skip, IO::SEEK_CUR)
      elsif  @size < @offset + bytes2skip
        raise InvalidFileException
      end
      @offset += bytes2skip
    end

    def skipBox
      if @size > 0
        if @size > @offset
          @file.seek(@size - @offset, IO::SEEK_CUR)
        elsif  @size < @offset
          raise InvalidFileException
        end
      else
        @file.seek(0, IO::SEEK_END) # lets move to the end of the file
      end
      @offset = @size
    end

    def initBaseParams
      @size = getInt32()

      if @size == 1
        @size = getInt64() # box size is 64-bit in case size ==1
      end

      @type = get32BitString()
    end

    def initialize parent, arg
      @parent = parent

      if arg.is_a? File
        @offset = 0
        @file = arg
        initBaseParams()
      else
        @offset = arg.offset
        @size   = arg.size
        @file   = arg.file
        @type   = arg.type
      end
    end

    def load
      skipBox
    end
  end

  class FullBox < Box
    attr_accessor :flags

    def initialize parent, arg
      super parent, arg
      @version = getInt8()
      @flags   = getInt24()
    end
  end

  class FileTypeBox < Box
    def load
      @major_brand   = get32BitString()
      @minor_version = getInt32()
      @compatible_brands = []
      while @size > @offset && !@file.eof?
        @compatible_brands << get32BitString()
      end

      raise InvalidFileException if @size != @offset
    end

    def is_major_brand_qt
      @major_brand == 'qt  '
    end

    def is_gt_in_compatible_brands
      @compatible_brands.include?('qt  ')
    end
  end

  class MovieHeaderBox < FullBox
    attr_accessor :creation_time, :modification_time, :timescale, :duration

    def load
      if @version == 1
        @creation_time = getInt64()
        @modification_time = getInt64()
        @timescale = getInt32()
        @duration = getInt64()
      else
        @creation_time = getInt32()
        @modification_time = getInt32()
        @timescale = getInt32()
        @duration = getInt32()
      end
      skipBox
    end
  end

  class TrackHeaderBox < FullBox
    attr_accessor :track_ID, :duration, :width, :height

    def load

      if @version == 1
        @creation_time = getInt64()
        @modification_time = getInt64()
        @track_ID = getInt32()
        skipNBytes(4) # const unsigned int(32) reserved = 0;
        @duration = getInt64()
      else
        @creation_time = getInt32()
        @modification_time = getInt32()
        @track_ID = getInt32()
        skipNBytes(4) # const unsigned int(32) reserved = 0;
        @duration = getInt32()
      end

      skipNBytes(8 + # const unsigned int(32)[2] reserved = 0;
                 2 + # template int(16) layer = 0;
                 2 + # template int(16) alternate_group = 0
                 2 + # template int(16) volume = {if track_is_audio 0x0100 else 0};
                 2 + # const unsigned int(16) reserved = 0;
                 9 * 4  # template int(32)[9] matrix= { 0x00010000,0,0,0,0x00010000,0,0,0,0x40000000 };
      )

      # width and height are 16.16 values
      @width  = getInt32() / 0x10000
      @height = getInt32() / 0x10000

      skipBox
    end
  end

  class MediaHeaderBox < FullBox
    attr_accessor :lang, :timescale

    def load
      if @version==1
        @creation_time = getInt64()
        @modification_time = getInt64()
        @timescale = getInt32()
        @duration = getInt64()
      else
        @creation_time = getInt32()
        @modification_time = getInt32()
        @timescale = getInt32()
        @duration = getInt32()
      end

      #bit(1) pad = 0;
      #unsigned int(5)[3] language; //
      language = getInt16
      language = (language << 1) & 0xFFFF
      @lang = ''

      3.times do
        l = (language >> 11) + 0x60
        @lang += l.chr
        language = (language << 5) & 0xFFFF
      end

      skipBox
    end
  end
  class HandlerBox < FullBox
    attr_accessor :handler_type

    def load
      @pre_defined = getInt32()
      @handler_type = get32BitString()
      # lets skip following fields
      #const unsigned int(32)[3] reserved = 0;
      #string name;
      skipBox
    end
  end
  class DataReferenceBox < FullBox
    def load
      entry_count = getInt32()
      raise InvalidFileException if entry_count != 1 # we don't support multi-source files
      box = FullBox.new(self, @file)
      raise InvalidFileException if box.flags != 1 # we don't support more-than-one-source files
      box.load
      @offset+= box.size
      skipBox
    end
  end
  class DataInformationBox < Box
    def load
      while @size > @offset && !@file.eof?
        box = Box.new(self, file)
        if 'dref' == box.type
          box = DataReferenceBox.new(self, box)
        else
          raise InvalidFileException
        end

        box.load
        @offset+= box.size
      end
      skipBox

    end
  end


  class SampleEntry < Box
    attr_accessor :data_reference_index, :codingname

    def initialize parent, arg
      super parent, arg
      # lets skip const unsigned int(8)[6] reserved = 0;
      @codingname = type()
      skipNBytes(6)
      @data_reference_index = getInt16()
    end
  end

  class AvcC < Box
    attr_accessor :sequesnceParameterSets, :pictureParameterSets
    def load
      # process according to this description http://thompsonng.blogspot.ru/2010/11/mp4-file-format-part-2.html
      raise "type incorrect" unless @type == "avcC"
      raise "wrong configuration version" unless getInt8() == 0x1
      skipNBytes(4)

      numOfSequesnceParameterSets = getInt8() & 0b11111 # get 5 lowest bits
      @sequesnceParameterSets = []
      numOfSequesnceParameterSets.times do
        sequenceParameterSetLength = getInt16
        @sequesnceParameterSets << getByteArray(sequenceParameterSetLength)
      end

      @pictureParameterSets = []
      numOfPictureParameterSets = getInt8()
      numOfPictureParameterSets.times do
        numOfPictureParameterSetLength = getInt16
        @pictureParameterSets << getByteArray(numOfPictureParameterSetLength)
      end
      skipBox
    end

  end
  class VisualSampleEntry < SampleEntry
    attr_accessor :width, :height, :compressorname

    def load
      raise "wrong coding name. only avc1 supoprted" unless codingname == 'avc1'
      pre_defined = getInt16
      reserved = getInt16
      pre_defined = getInt32Array(3)
      @width  = getInt16
      @height = getInt16
      horizresolution = getInt32
      vertresolution  = getInt32
      reserved = getInt32
      frame_count = getInt16
      raise InvalidFileException if frame_count != 1
      @compressorname = getFixedSizeString(32)
      depth = getInt16
      pre_defined = getInt16

      # lets get avcC params
                                                          # box size  box type
      raise "wrong avc1 container" unless @size > @offset + 4         + 4
      parent.avcC =  box = AvcC.new(self, @file)
      box.load
      @offset+= box.size

      skipBox
    end
  end

  class EsdsBox < Box
    attr_accessor :object_type, :sample_rate, :sample_rate_index, :chan_config
    MP4ESDESCRTAG = 0x03
    MP4DECCONFIGDESCRTAG = 0x04
    MP4DECSPECIFICDESCRTAG = 0x5
    AVPRIV_MPEG4AUDIO_SAMPLE_RATES =[96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]
    FF_MPEG4AUDIO_CHANNELS = [0, 1, 2, 3, 4, 5, 6, 8]

    def load
      @object_type = @sample_rate = @sample_rate_index = @chan_config = 0
      getInt32 # version + flags
      tag,len = mp4_read_descr

      if tag == MP4ESDESCRTAG
          mp4_parse_es_descr()
      else
          getInt16 # ID
      end
      tag, len = mp4_read_descr
      if tag == MP4DECCONFIGDESCRTAG
        mp4_read_dec_config_descr
      end
      skipBox
    end

    private

    def mp4_read_dec_config_descr
      object_type_id = getInt8
      getInt8   # stream type
      getInt24 # buffer size db
      getInt32 # max bitrate
      getInt32 # avg bitrate

      tag, len = mp4_read_descr()

      if tag == MP4DECSPECIFICDESCRTAG
        @object_type, @sample_rate, @sample_rate_index, @chan_config  = mpeg4audio_get_config()
      end

    end

    def mpeg4audio_get_config
      #@object_type, @sample_rate, @chan_config
      first_byte = getInt8()
      second_byte = getInt8()
      object_type = (first_byte & 0xF8) >> 3 # get object_type. object_id is 5 higher bits of byte so lets cut 3 lower bits

      sample_rate_index = ((first_byte & 0x7) << 1) + (second_byte >> 7)
      sample_rate =  sample_rate_index == 0x0f ? getInt24() : AVPRIV_MPEG4AUDIO_SAMPLE_RATES[sample_rate_index]
      chan_config = (second_byte >> 3) & 0xF
      if (chan_config < FF_MPEG4AUDIO_CHANNELS.size)
        chan_config = FF_MPEG4AUDIO_CHANNELS[chan_config]
      end

      return object_type, sample_rate, sample_rate_index, chan_config
    end

    def mp4_read_descr
           #   tag,     len
      return getInt8(), mp4_read_descr_len()
    end

    def mp4_read_descr_len
        len = 0
        count = 4
        while (count = count-1)>=0  do
          c = getInt8
          len = (len << 7) | (c & 0x7f)
          break if (0x00 == (c & 0x80))
        end
      return len
    end

    def mp4_parse_es_descr
      es_id = getInt16 # es_id
      flags = getInt8
      if (flags & 0x80) != 0 # streamDependenceFlag
         getInt16
      end

      if (flags & 0x40) != 0 # URL_Flag
        len = getInt8
        skipNBytes(len)
      end

      if (flags & 0x20) != 0 # OCRstreamFlag
         getInt16
      end
    end
  end

  class ItunesWaveBox < Box
    attr_accessor :esds
    def load
      while @size > @offset && !@file.eof?
        box = Box.new(self, file)
        if 'esds' == box.type
          @esds = box = EsdsBox.new(self, box)
        end
        box.load
        @offset+= box.size
      end
      skipBox
    end
  end
  class AudioSampleEntry < SampleEntry
    attr_accessor :channelcount, :samplesize, :samplerate
    def load
      raise "wrong coding name. only mp4a supoprted" unless codingname == 'mp4a'
      version = getInt16
      getInt16 # revision level
      getInt32 # vendor

      @channelcount = getInt16
      @samplesize = getInt16
      pre_defined = getInt16
      reserved = getInt16
      @samplerate = getInt32  >> 16
      moov = parent.parent.parent.parent.parent.parent
      ftyp = moov.ftyp

      if ftyp.is_major_brand_qt || ftyp.is_gt_in_compatible_brands
        if version == 1
          @samples_per_frame = getInt32
          @bytes_per_packet = getInt32 # bytes per packet
          @bytes_per_frame = getInt32
          @bytes_per_sample = getInt32
        elsif version == 2
          getInt32 # sizeof struct only
          @sample_rate = getInt64
          @channelcount = avio_rb32(pb);
          raise "wrong v2 format" unless getInt32() == 0x7F000000
          @bits_per_coded_sample = getInt32 # bits per channel if sound is uncompressed */
          getInt32 # lpcm format specific flag
          @bytes_per_frame = getInt32 # bytes per audio packet if constant
          @samples_per_frame = getInt32 # lpcm frames per audio packet if constant

        end

      end

      raise "wrong mp4 container" unless @size > @offset + 4         + 4
      esds_pretender = Box.new(self, @file)

      if esds_pretender.type == 'wave'
        wave = ItunesWaveBox.new self, esds_pretender
        wave.load
        @offset+= wave.size
        esds = wave.esds

      elsif esds_pretender.type == 'esds'
        esds = EsdsBox.new(self, esds_pretender)
        esds.load
        @offset+= esds.size
      else
             raise "wrong mp4a container. cannot find neither wave nor esds"
      end
      parent.esds = esds
      # process esds
      skipBox
    end
  end

  # stts
  class TimeToSampleBox < FullBox
    attr_accessor :time_2_sample_info

    def load
      entry_count = getInt32
      @time_2_sample_info = []
      entry_count.times do
        @time_2_sample_info << [getInt32, getInt32]
      end
      skipBox
    end
  end

  # ctts
  class CompositionOffsetBox < FullBox
    attr_accessor :composition_sample_info
    def load
      raise "only version 0 supported for ctts" if @version != 0
      entry_count = getInt32
      @composition_sample_info = []
      entry_count.times do
        @composition_sample_info << [getInt32, getInt32]
      end
      skipBox
    end
  end

  #stss
  class SyncSampleBox < FullBox
    attr_accessor :sync_sample_info
    def load
      entry_count = getInt32
      @sync_sample_info = []
      entry_count.times do
        @sync_sample_info << getInt32
      end
      skipBox
    end
  end

  # 'stsd'
  class SampleDescriptionBox < FullBox
    attr_accessor :vide, :soun, :avcC, :esds

    def load
                    #stbl  ->minf ->mdia ->trak
      handler_type = parent.parent.parent.handler.handler_type
      entry_count = getInt32()
      raise InvalidFileException if entry_count != 1
      if handler_type == 'vide'
        @vide = box = VisualSampleEntry.new self, @file
      else  handler_type == 'soun'
        @soun = box = AudioSampleEntry.new self, @file
      end
      box.load
      @offset+= box.size
      skipBox
    end
  end

  # stsc
  class SampleToChunkBox < FullBox
    attr_accessor :sample_info
    def load
      entry_count = getInt32
      @sample_info = []
      entry_count.times do
                        # first_chunk            samples_per_chunk  sample_description_index
        @sample_info << [getInt32,               getInt32,          getInt32]
      end
      skipBox
    end
  end

  # stsz
  class SampleSizeBox < FullBox
    attr_accessor :sample_size, :sample_count, :sample_sizes
    def load
      @sample_size  = getInt32
      @sample_count = getInt32
      if @sample_size == 0
        @sample_sizes = []
        @sample_count.times do
          @sample_sizes << getInt32
        end
      end
    end
  end

  # stco
  class ChunkOffsetBox < FullBox
    attr_accessor :chunk_offsets
    def load
      entry_count = getInt32
      @chunk_offsets = []
      entry_count.times do
        @chunk_offsets << getInt32
      end
    end
  end

  # co64
  class ChunkLargeOffsetBox < FullBox
    attr_accessor :chunk_offsets
    def load
      entry_count = getInt32
      @chunk_offsets = []
      entry_count.times do
        @chunk_offsets << getInt64
      end
    end
  end

  # stbl
  class SampleTableBox < Box
    attr_accessor :stsd, :stts, :ctts, :stss, :stsc, :stsz, :stco, :co64
    def load
      while @size > @offset && !@file.eof?
        box = Box.new(self, file)
        if 'stsd' == box.type
          @stsd = box = SampleDescriptionBox.new(self, box)
        elsif 'stts' == box.type
          @stts = box = TimeToSampleBox.new(self, box)
        elsif 'ctts' == box.type
          @ctts = box = CompositionOffsetBox.new(self, box)
        elsif 'stss' == box.type
          @stss = box = SyncSampleBox.new(self, box)
        elsif 'stsc' == box.type
          @stsc = box = SampleToChunkBox.new(self, box)
        elsif 'stsz' == box.type
          @stsz = box = SampleSizeBox.new(self, box)
        elsif 'stco' == box.type
          @stco = box = ChunkOffsetBox.new(self, box)
        elsif 'co64' == box.type
          @co64 = box = ChunkLargeOffsetBox.new(self, box)
        end
        box.load
        @offset+= box.size
      end

      # minf ->mdia ->trak
      handler_type = parent.parent.handler.handler_type
      if handler_type == 'vide'
        raise InvalidFileException unless @stsd && @stts && @stss && @stsc && @stsz && (@stco || @co64)
      elsif  handler_type == 'soun'
        raise InvalidFileException unless @stsd && @stts && !@stss && !@ctts && @stsc && @stsz && (@stco || @co64)
      end

      skipBox
    end
  end

  # minf
  class MediaInformationBox < Box
    attr_accessor :stbl
    def load
      while @size > @offset && !@file.eof?
        box = Box.new self, file
        if 'dinf' == box.type
          box = DataInformationBox.new self,  box
        elsif 'stbl' == box.type
          @stbl = box = SampleTableBox.new self, box
        end

        box.load
        @offset+= box.size
      end
      skipBox
    end
  end

  # mdia
  class MediaBox < Box
    attr_accessor :mdhd, :handler, :minf
    def load
      while @size > @offset && !@file.eof?
        box = Box.new(self, file)
        if 'mdhd' == box.type
          @mdhd = box = MediaHeaderBox.new(self, box)
        elsif 'hdlr' == box.type
          @handler = box = HandlerBox.new(self, box)
        elsif 'minf' == box.type
          @minf = box = MediaInformationBox.new(self, box)
        end
        box.load
        @offset+= box.size
      end
      skipBox
    end
  end

  # trak
  class TrackBox < Box
    attr_accessor :tkhd, :mdia

    def load
      while @size > @offset && !@file.eof?
        box = Box.new(self, file)
        if 'tkhd' == box.type
          @tkhd = box = TrackHeaderBox.new(self, box)
        elsif 'mdia' == box.type
          @mdia = box = MediaBox.new(self, box)
        end
        box.load
        @offset+= box.size
      end
      skipBox
    end
  end

  # moov
  class MovieBox < Box
   attr_accessor :mvhd, :traks, :ftyp

   def initialize parent, arg, ftyp
     super parent, arg
     @ftyp = ftyp
   end

   def load
     @mvhd = nil
     @traks = []
     while @size > @offset && !@file.eof?
       box = Box.new(self, file)
       if 'mvhd' == box.type
         @mvhd = box =  MovieHeaderBox.new(self, box)
       elsif 'trak' == box.type
         @traks << box = TrackBox.new(self, box)
       end

       box.load
       @offset+= box.size
     end
     skipBox
   end
  end

  def load fileName
    File.open fileName, 'rb' do |file|
      # let find ftype first
      first_box = true
      @fileType = nil

      while not file.eof? do
        box = Box.new(self, file)
        if 'ftyp' == box.type
          box = @fileType = FileTypeBox.new(nil, box)
        end
        box.load

        break if @fileType
        first_box = false
      end

      raise "was not able to find ftyp" unless @fileType

      unless first_box and @fileType
        # lets begin from
        file.seek(0, IO::SEEK_SET)
      end

      while not file.eof? do
        box = Box.new(self, file)
        if 'moov' == box.type
          box = @movieBox = MovieBox.new(nil, box, @fileType)
        end
        box.load
      end
    end
  end

  attr_accessor :fileType, :movieBox

  def getMediaInfo(mediaFile)
    p "Movie Info creation_time= #{mediaFile.movieBox.mvhd.creation_time}"\
  ",modification time=#{mediaFile.movieBox.mvhd.modification_time}"\
  ",timescale=#{mediaFile.movieBox.mvhd.timescale}"\
  ",duration=#{mediaFile.movieBox.mvhd.duration}"

    mediaFile.movieBox.traks.each do |trak|
      p "Trak info Id=#{trak.tkhd.track_ID}"\
    ",duration=#{trak.tkhd.duration}"\
    ",width=#{trak.tkhd.width}"\
    ",height=#{trak.tkhd.height}"
      p "Media Header box. lang=#{trak.mdia.mdhd.lang}"
      p "Media Handler box.handler_type=#{trak.mdia.handler.handler_type}"
      next unless trak.mdia.handler.handler_type == 'vide' or trak.mdia.handler.handler_type == 'soun'

      stbl = trak.mdia.minf.stbl
      if stbl.stsd.vide
        p "Sample description box width=#{stbl.stsd.vide.width}"\
    ",height=#{stbl.stsd.vide.height}"\
    ",compressorname=#{stbl.stsd.vide.compressorname}"
      elsif stbl.stsd.soun
        p "Sample description channelcount=#{stbl.stsd.soun.channelcount}"\
    ",samplesize=#{stbl.stsd.soun.samplesize}"\
    ",samplerate=#{stbl.stsd.soun.samplerate}"
      end
      p "------------------------------------------------"
    end


  end
end

class MpegTs
  class BaseTSPacket

    def initialize pid, payload_unit_start_indicator, adaptation_field_control, continuity_counter
      @packet = Array.new 188, 0xFF
      @packet[0] = 0x47 # sync byte

      @packet[1] = 0
      @packet[1] |= 0b1000000 if payload_unit_start_indicator
      @packet[1] |= ((pid >> 8 ) & 0x1F) # 5 higher bits

      @packet[2] = pid & 0xFF # 8 upper bits

      @packet[3] = 0
      @packet[3] |= adaptation_field_control << 4
      @packet[3] |= (continuity_counter & 0xF)

      @offset = 4
    end

    def set_adaptation_field new_af_value
      @packet[3] |= new_af_value << 4
    end

    AV_CRC_32_IEEE = [
        0x00000000, 0xB71DC104, 0x6E3B8209, 0xD926430D, 0xDC760413, 0x6B6BC517,
        0xB24D861A, 0x0550471E, 0xB8ED0826, 0x0FF0C922, 0xD6D68A2F, 0x61CB4B2B,
        0x649B0C35, 0xD386CD31, 0x0AA08E3C, 0xBDBD4F38, 0x70DB114C, 0xC7C6D048,
        0x1EE09345, 0xA9FD5241, 0xACAD155F, 0x1BB0D45B, 0xC2969756, 0x758B5652,
        0xC836196A, 0x7F2BD86E, 0xA60D9B63, 0x11105A67, 0x14401D79, 0xA35DDC7D,
        0x7A7B9F70, 0xCD665E74, 0xE0B62398, 0x57ABE29C, 0x8E8DA191, 0x39906095,
        0x3CC0278B, 0x8BDDE68F, 0x52FBA582, 0xE5E66486, 0x585B2BBE, 0xEF46EABA,
        0x3660A9B7, 0x817D68B3, 0x842D2FAD, 0x3330EEA9, 0xEA16ADA4, 0x5D0B6CA0,
        0x906D32D4, 0x2770F3D0, 0xFE56B0DD, 0x494B71D9, 0x4C1B36C7, 0xFB06F7C3,
        0x2220B4CE, 0x953D75CA, 0x28803AF2, 0x9F9DFBF6, 0x46BBB8FB, 0xF1A679FF,
        0xF4F63EE1, 0x43EBFFE5, 0x9ACDBCE8, 0x2DD07DEC, 0x77708634, 0xC06D4730,
        0x194B043D, 0xAE56C539, 0xAB068227, 0x1C1B4323, 0xC53D002E, 0x7220C12A,
        0xCF9D8E12, 0x78804F16, 0xA1A60C1B, 0x16BBCD1F, 0x13EB8A01, 0xA4F64B05,
        0x7DD00808, 0xCACDC90C, 0x07AB9778, 0xB0B6567C, 0x69901571, 0xDE8DD475,
        0xDBDD936B, 0x6CC0526F, 0xB5E61162, 0x02FBD066, 0xBF469F5E, 0x085B5E5A,
        0xD17D1D57, 0x6660DC53, 0x63309B4D, 0xD42D5A49, 0x0D0B1944, 0xBA16D840,
        0x97C6A5AC, 0x20DB64A8, 0xF9FD27A5, 0x4EE0E6A1, 0x4BB0A1BF, 0xFCAD60BB,
        0x258B23B6, 0x9296E2B2, 0x2F2BAD8A, 0x98366C8E, 0x41102F83, 0xF60DEE87,
        0xF35DA999, 0x4440689D, 0x9D662B90, 0x2A7BEA94, 0xE71DB4E0, 0x500075E4,
        0x892636E9, 0x3E3BF7ED, 0x3B6BB0F3, 0x8C7671F7, 0x555032FA, 0xE24DF3FE,
        0x5FF0BCC6, 0xE8ED7DC2, 0x31CB3ECF, 0x86D6FFCB, 0x8386B8D5, 0x349B79D1,
        0xEDBD3ADC, 0x5AA0FBD8, 0xEEE00C69, 0x59FDCD6D, 0x80DB8E60, 0x37C64F64,
        0x3296087A, 0x858BC97E, 0x5CAD8A73, 0xEBB04B77, 0x560D044F, 0xE110C54B,
        0x38368646, 0x8F2B4742, 0x8A7B005C, 0x3D66C158, 0xE4408255, 0x535D4351,
        0x9E3B1D25, 0x2926DC21, 0xF0009F2C, 0x471D5E28, 0x424D1936, 0xF550D832,
        0x2C769B3F, 0x9B6B5A3B, 0x26D61503, 0x91CBD407, 0x48ED970A, 0xFFF0560E,
        0xFAA01110, 0x4DBDD014, 0x949B9319, 0x2386521D, 0x0E562FF1, 0xB94BEEF5,
        0x606DADF8, 0xD7706CFC, 0xD2202BE2, 0x653DEAE6, 0xBC1BA9EB, 0x0B0668EF,
        0xB6BB27D7, 0x01A6E6D3, 0xD880A5DE, 0x6F9D64DA, 0x6ACD23C4, 0xDDD0E2C0,
        0x04F6A1CD, 0xB3EB60C9, 0x7E8D3EBD, 0xC990FFB9, 0x10B6BCB4, 0xA7AB7DB0,
        0xA2FB3AAE, 0x15E6FBAA, 0xCCC0B8A7, 0x7BDD79A3, 0xC660369B, 0x717DF79F,
        0xA85BB492, 0x1F467596, 0x1A163288, 0xAD0BF38C, 0x742DB081, 0xC3307185,
        0x99908A5D, 0x2E8D4B59, 0xF7AB0854, 0x40B6C950, 0x45E68E4E, 0xF2FB4F4A,
        0x2BDD0C47, 0x9CC0CD43, 0x217D827B, 0x9660437F, 0x4F460072, 0xF85BC176,
        0xFD0B8668, 0x4A16476C, 0x93300461, 0x242DC565, 0xE94B9B11, 0x5E565A15,
        0x87701918, 0x306DD81C, 0x353D9F02, 0x82205E06, 0x5B061D0B, 0xEC1BDC0F,
        0x51A69337, 0xE6BB5233, 0x3F9D113E, 0x8880D03A, 0x8DD09724, 0x3ACD5620,
        0xE3EB152D, 0x54F6D429, 0x7926A9C5, 0xCE3B68C1, 0x171D2BCC, 0xA000EAC8,
        0xA550ADD6, 0x124D6CD2, 0xCB6B2FDF, 0x7C76EEDB, 0xC1CBA1E3, 0x76D660E7,
        0xAFF023EA, 0x18EDE2EE, 0x1DBDA5F0, 0xAAA064F4, 0x738627F9, 0xC49BE6FD,
        0x09FDB889, 0xBEE0798D, 0x67C63A80, 0xD0DBFB84, 0xD58BBC9A, 0x62967D9E,
        0xBBB03E93, 0x0CADFF97, 0xB110B0AF, 0x060D71AB, 0xDF2B32A6, 0x6836F3A2,
        0x6D66B4BC, 0xDA7B75B8, 0x035D36B5, 0xB440F7B1, 0x00000001
    ]


    def crc32(from, to)

      crc = 0xFFFFFFFF
      (to-from+1).times{|index|
        crc = AV_CRC_32_IEEE[(crc & 0xFF) ^ @packet[from+index]] ^ (crc >> 8)
      }

      [crc & 0xFF,  (crc >> 8) & 0xFF, (crc >> 16) & 0xFF, (crc >> 24) & 0xFF]
    end

    def write file
      file.write @packet.pack('C*')
    end
  end

  class TSPatPacket < BaseTSPacket
    def initialize

=begin   This is how we can generate valid PAT, but in production I'd prefer to just return const
          # pid
      super 0,
            true, # payload_unit_start_indicator == true for PAT
            0b01, # No adaptation_field, payload only
            0b00 #  CC == 0 for PAT

      @packet[4] = 0 # Table 2-29 – Program specific information pointer
      @packet[5] = 0 # Table 2-31 – table_id assignment values program_association_section == 0x00
      @packet[6] = 0xB0 # section syntax indicator is 1, then '0' and two reserved 11 and 0000 for section length
      @packet[7] = 0x0D # we support only one program in the stream and we know exactly size
      @packet[8] = 0x00 # low transport stream id byte
      @packet[9] = 0x01 # high transport stream id byte. id == 0x01 BTW
      @packet[10] = 0xC1 # reserved + version number + current_next_indicator are always teh same
      @packet[11] = 0x0 # section number
      @packet[12] = 0x0 # last section number
      @packet[13] = 0x0 # high program number byte
      @packet[14] = 0x1 # low program number byte
      @packet[15] = 0xEF # program map pid is 0x0FFF
      @packet[16] = 0xFF

      crc = crc32(5, 16)
      @packet[17] = crc[0]
      @packet[18] = crc[1]
      @packet[19] = crc[2]
      @packet[20] = crc[3]

      #what to say. I know CRC in that case
      # quick sanity check for crc32
      raise "wrong crc32" unless crc == [0x36, 0x90, 0xE2, 0x3D]
=end
      @packet=[0x47, 0x40, 0x00, 0x10, 0x00, 0x00, 0xB0, 0x0D, 0x00, 0x01, 0xC1, 0x00, 0x00, 0x00, 0x01, 0xEF,
               0xFF, 0x36, 0x90, 0xE2, 0x3D, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
               0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
               0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
               0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
               0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
               0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
               0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
               0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
               0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
               0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
               0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
      @offset = 22
      # NOTE: during nimble implementation I'll just create binary const array and will always send it as PAT
    end
  end

  def createProgramAssociationTable
    TSPatPacket.new
  end

  class TSProgramMapSectionPacket < BaseTSPacket
    def initialize(isobasemediafile)
=begin  This is how we can generate valid PMT, but in production I'd prefer to just return consts
      super 0xFFF, # ProgramMap PID is const
            true, # payload_unit_start_indicator == true for PAT
            0b01, # No adaptation_field, payload only
            0b00 #  CC == 0 for MAP
      @packet[4] = 0 # Table 2-29 – Program specific information pointer
      @packet[5] = 2 # Table 2-31 – table_id assignment values program_association_section == 0x02
      @packet[6] = 0xB0 # section syntax indicator is 1, then '0' and two reserved 11 and 0000 for section length
      @packet[7] = 23   # section length
      @packet[8] = 0x0 # high program number byte
      @packet[9] = 0x1 # low program number byte
      @packet[10] = 0xC1 # reserved + version number + current_next_indicator are always the same
      @packet[11] = 0x0 # section number
      @packet[12] = 0x0 # last section number

      @packet[13] = 0xE1 # 3 reserved bits are 111 + 5 hight bits for PCR_PID
      @packet[14] = 0x00 # PCR_PID here is 256. we will use 256 are video stream PID

      @packet[15] = 0xF0 # 4 reserved bits are 1111 + 4 hight bits for program_info_length
      @packet[16] = 0x00 # program_info_length here is 0

      @packet[17] = 0x1B # "AVC video stream as defined in ITU-T Rec. H.264 | ISO/IEC 14496-10 Video"
      @packet[18] = 0xE1 #elementary PID is 256
      @packet[19] = 0x00 #elementary PID is 256
      @packet[20] = 0xF0 # reserved + 0 length for Es info
      @packet[21] = 0x00


      @packet[22] = 0x0F # "ISO/IEC 13818-7 Audio with ADTS transport syntax",
      @packet[23] = 0xE1 #elementary PID is 257
      @packet[24] = 0x01 #elementary PID is 257
      @packet[25] = 0xF0 # reserved + 0 length for Es info
      @packet[26] = 0x00


      crc32 = crc32(5, 26) # lets get crc32 from 5 to 26 byte
      @packet[27] = crc32[0]
      @packet[28] = crc32[1]
      @packet[29] = crc32[2]
      @packet[30] = crc32[3]
      @offset = 36
=end

      video_presented = false
      audio_presented = false

      isobasemediafile.movieBox.traks.each{|trak|
        video_presented = true if trak.mdia.handler.handler_type == 'vide'
        audio_presented = true if trak.mdia.handler.handler_type == 'soun'
        break if video_presented && audio_presented
      }


      if video_presented and audio_presented
        #video+audio, elementary PID is 256 for video PCR_PID is 256 as well, audio' PID is 257. we should consider this during PES generation
        @packet = [0x47, 0x4F, 0xFF, 0x10, 0x00, 0x02, 0xB0, 0x17, 0x00, 0x01, 0xC1, 0x00, 0x00, 0xE1, 0x00, 0xF0,
         0x00, 0x1B, 0xE1, 0x00, 0xF0, 0x00, 0x0F, 0xE1, 0x01, 0xF0, 0x00, 0x2F, 0x44, 0xB9, 0x9B, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
        @offset = 36 # not used but just for consistency sake
      elsif video_presented
        #video only, elementary PID is 256 PCR_PID is 256 as well. we should consider this during PES generation
        @packet = [0x47, 0x4F, 0xFF, 0x10, 0x00, 0x02, 0xB0, 0x12, 0x00, 0x01, 0xC1, 0x00, 0x00, 0xE1, 0x00, 0xF0,
         0x00, 0x1B, 0xE1, 0x00, 0xF0, 0x00, 0x15, 0xBD, 0x4D, 0x56, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
        @offset = 31  # not used but just for consistency sake
      elsif audio_presented
        #audio only, elementary PID is 256 PCR_PID is 256 as well. we should consider this during PES generation
        @packet = [0x47, 0x4F, 0xFF, 0x10, 0x00, 0x02, 0xB0, 0x12, 0x00, 0x01, 0xC1, 0x00, 0x00, 0xE1, 0x00, 0xF0,
         0x00, 0x0F, 0xE1, 0x00, 0xF0, 0x00, 0xB6, 0x9B, 0xC0, 0xD9, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
         0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]
        @offset = 31 # not used but just for consistency sake
      else
        raise 'neither video nor audio trak exists'
      end

    end
  end

  def createProgramMapTable isobasemediafile
    TSProgramMapSectionPacket.new(isobasemediafile)
  end

  class PESPacket < BaseTSPacket
    PES_VIDEO_STREAM_BEGIN = 0b1110_0000
    PES_AUDIO_STREAM_BEGIN = 0b1100_0000
    attr_reader :tail

    def addAdaptationField random_access_indicator, pcr, stuff_bytes_count
      set_adaptation_field(0b11)
      unless !random_access_indicator && !pcr && stuff_bytes_count == 1

        adaptation_field_length = 1 + (pcr ? 6 : 0)
        stuff_bytes_count-= 2
        stuff_bytes_count = 0 if stuff_bytes_count < 0

        if pcr
          stuff_bytes_count-= 6
          stuff_bytes_count = 0 if stuff_bytes_count < 0
        end

        @packet[@offset] = adaptation_field_length + stuff_bytes_count
        @packet[@offset +1] = 0
        @packet[@offset +1] |= (1 << 6) if random_access_indicator
        @packet[@offset +1] |= (1 << 4) if pcr

        if pcr
          #program_clock_reference_base 33 uimsbf
          #Reserved 6 bslbf
          #program_clock_reference_extension 9 uimsbf
          pcr_high = pcr / 300
          pcr_low = pcr % 300
          pcr_high_first_part = pcr_high >> 1

          @packet[@offset + 2] = (pcr_high_first_part & 0xFF000000) >> 24
          @packet[@offset + 3] = (pcr_high_first_part & 0xFF0000) >> 16
          @packet[@offset + 4] = (pcr_high_first_part & 0xFF00) >> 8
          @packet[@offset + 5] = pcr_high_first_part & 0xFF
          @packet[@offset + 6] =0b01111110
          @packet[@offset + 6] |= (pcr_high & 0x1) << 7
          @packet[@offset + 6] |= pcr_low >> 8
          @packet[@offset + 7] = pcr_low & 0xFF
        end

        @offset+=stuff_bytes_count + adaptation_field_length + 1
      else
        @packet[@offset] = 0
        @offset+=1
      end
    end

    def addPESHeader pts, dts, payloadsize, is_video
      @packet[@offset] = 0x0;@packet[@offset+1] = 0x0;@packet[@offset+2] = 0x1
      @packet[@offset+3] = is_video ? PES_VIDEO_STREAM_BEGIN : PES_AUDIO_STREAM_BEGIN
      pes_packet_length = 3 + payloadsize + (pts ? 5 : 0) + (pts and pts!=dts ? 5 : 0)
      @packet[@offset+4] = pes_packet_length / 0x100
      @packet[@offset+5] = pes_packet_length % 0x100

      @packet[@offset+6] = 0b10 << 6

      #PTS_DTS_flags 2 bslbf
      if !pts
        @packet[@offset+7] = 0
      elsif pts == dts
        @packet[@offset+7] = 0b10 << 6
      else
        @packet[@offset+7] = 0b11 << 6
      end

      #PES_header_data_length 8 uimsbf
      @packet[@offset+8] = (pts ? 5 : 0) + (pts and pts!=dts ? 5 : 0)


      if pts
        @packet[@offset+9] = 0b00100001
        @packet[@offset+9]|= (pts >> 30) << 1

        @packet[@offset+10] = (pts >> 22) & 0xFF
        @packet[@offset+11] = 1
        @packet[@offset+11] |= ((pts >> 15) & 0xFF) << 1
        @packet[@offset+12] = ((pts >> 7) & 0xFF)
        @packet[@offset+13] = 1
        @packet[@offset+13] |= (pts & 0b1111111) << 1

        if pts != dts
          @packet[@offset+9]|= 0b00010000

          @packet[@offset+14] = 0b00100001
          @packet[@offset+14]|= (dts >> 30) << 1

          @packet[@offset+15] = (dts >> 22) & 0xFF
          @packet[@offset+16] = 1
          @packet[@offset+16] |= ((dts >> 15) & 0xFF) << 1
          @packet[@offset+17] = ((dts >> 7) & 0xFF)
          @packet[@offset+18] = 1
          @packet[@offset+18] |= (dts & 0b1111111) << 1
          @offset+= 5
        end

        @offset+= 14

      else
        @offset+= 9
      end
    end

    def getChunkOffset stbl, sample_index
      chunk_id = 1
      chunk_samples = 0
      stsc_index = 0
      chunk_offset_table = stbl.stco ? stbl.stco.chunk_offsets  : stbl.co64.chunk_offsets
      chunks_count = chunk_offset_table.size
      offset_in_chunk = 0
      chunk_offset = 0
      chunk_id = 1
      sample_size = -1

      (sample_index + 1).times do |sample_id|
        sample_size = stbl.stsz.sample_size != 0 ? stbl.stsz.sample_size : stbl.stsz.sample_sizes[sample_id]

        stsc_item = stbl.stsc.sample_info[stsc_index]
        chunk_samples+= 1
        if chunk_samples > stsc_item[1] # second element is samples-per-chunk
          chunk_id+= 1
          chunk_samples=1
          offset_in_chunk = 0
        end

        raise "chunk_id > total chunk count" if chunk_id > chunks_count

        if stbl.stsc.sample_info[stsc_index + 1] && stbl.stsc.sample_info[stsc_index + 1][0] == chunk_id
          chunk_samples= 1
          stsc_index+= 1
          offset_in_chunk = 0
        end
        offset_in_chunk+=sample_size unless sample_id == sample_index

      end
      chunk_offset = chunk_offset_table[chunk_id -1]

      return chunk_offset+ offset_in_chunk, sample_size
    end

    def isRandomAccessFrame stbl, sample_index
      stss = stbl.stss # sync sample box
      return true unless stss # If the sync sample box is not present, every sample is a random access point.

      stss.sync_sample_info.each do |sync_sample_id|
        return true if sample_index == (sync_sample_id-1)
        break if sample_index> sync_sample_id-1
      end
      return false
    end

    def patchSampleBuffer stbl, sample_index, buffer
      if stbl.stsd.vide
        resulting_sample_buffer = []
        resulting_sample_buffer << [0x00, 0x00, 0x00, 0x01, 0x09, 0xF0, 0x00, 0x00, 0x00, 0x01]

        add_decoder_info = false

        stbl.stss.sync_sample_info.each do |sample_id|
          add_decoder_info = true if sample_id == sample_index+1
          break if sample_id >= sample_index+1
        end

        while(buffer.size > 0)
          if add_decoder_info
            # add decoder info from avcC
            stbl.stsd.avcC.sequesnceParameterSets.each do |sequesnceParameterSet|
              resulting_sample_buffer << sequesnceParameterSet
              resulting_sample_buffer << [0x0, 0x0, 0x0, 0x1]
            end

            stbl.stsd.avcC.pictureParameterSets.each do |pictureParameterSet|
              resulting_sample_buffer << pictureParameterSet
              resulting_sample_buffer << [0x0, 0x0, 0x0, 0x1]
            end
            add_decoder_info = false
          end

          sample_part_size = 0x1000000 * buffer[0] + 0x10000  * buffer[1] + 0x100 * buffer[2] + buffer[3]
          raise "wrong file format" unless buffer.slice!(0, 4).size == 4 # lets remove sample size
          raise "wrong file format" unless (sample_part = buffer.slice!(0, sample_part_size)).size  == sample_part_size
          resulting_sample_buffer << sample_part

          resulting_sample_buffer << [0x0, 0x0, 0x0, 0x1] unless buffer.empty?
        end

        return resulting_sample_buffer.flatten
      end

    end
    def patchAdtsBuffer  stbl, buffer
=begin
      /* adts_fixed_header */
      0
      put_bits(&pb, 12, 0xfff);   /* syncword */
      put_bits(&pb, 1, 0);        /* ID */
      put_bits(&pb, 2, 0);        /* layer */
      put_bits(&pb, 1, 1);        /* protection_absent */
      2
      put_bits(&pb, 2, ctx->objecttype); /* profile_objecttype */
      put_bits(&pb, 4, ctx->sample_rate_index);
      put_bits(&pb, 1, 0);        /* private_bit */
      put_bits(&pb, 3, ctx->channel_conf); /* channel_configuration */
      put_bits(&pb, 1, 0);        /* original_copy */
      put_bits(&pb, 1, 0);        /* home */

      /* adts_variable_header */
      put_bits(&pb, 1, 0);        /* copyright_identification_bit */
      put_bits(&pb, 1, 0);        /* copyright_identification_start */
      put_bits(&pb, 13, full_frame_size); /* aac_frame_length */
      put_bits(&pb, 11, 0x7ff);   /* adts_buffer_fullness */
      put_bits(&pb, 2, 0);        /* number_of_raw_data_blocks_in_frame */
=end
      adts_header=[0xFF, 0xF1, 0x0, 0x0, 0x0, 0x00, 0xFC]
      esds = stbl.stsd.esds
      #object_type, :sample_rate, :chan_config
      adts_header[2] = (((esds.object_type-1)& 0x3) << 6) | ((esds.sample_rate_index & 0xF) << 2) | ((esds.chan_config & 0x7) >> 2)

      full_fram_size = buffer.size + 7
      adts_header[3] = ((esds.chan_config & 0x3) << 6) | (full_fram_size >> 11)
      adts_header[4] = (full_fram_size >> 3) & 0xFF
      adts_header[5] = (full_fram_size & 0x7) << 5 | 0x1F

      return adts_header + buffer
    end

    def self.time_scale(stbl, t)
           # minf mdia
      (t * 90000 + stbl.parent.parent.mdhd.timescale / 2) / stbl.parent.parent.mdhd.timescale
    end
    def self.build_pts_dts(stbl, sample_index)
      stts = stbl.stts
      ctts = stbl.ctts
      current_stts_index = 0
      backet_index = 0
      dts = dts_delta= 0
      (sample_index).times do |_|
        if backet_index >= stts.time_2_sample_info[current_stts_index][0]
          current_stts_index+=1
          backet_index = 0
        end
        dts+= stts.time_2_sample_info[current_stts_index][1]
      end

      current_ctts_index = 0
      backet_index = 0

      if ctts
        (sample_index+1).times do |_|
          if backet_index >= ctts.composition_sample_info[current_ctts_index][0]
            current_ctts_index+=1
            backet_index = 0
          end
          dts_delta= ctts.composition_sample_info[current_ctts_index][1] # only last one matter since CT(n) = DT(n) + CTTS(n) according to 8.6.1.3.1
          backet_index+=1
        end
      end

      return PESPacket.time_scale(stbl, dts + dts_delta), PESPacket.time_scale(stbl, dts)
    end


    def initialize(params)
      super params[:pid], # ProgramMap PID is const
            params[:pusi],
            0b01, # No adaptation_field, payload only
            params[:cc]

      buffer = params[:buffer]

      unless buffer
        stbl   = params[:stbl]
        sample_index = params[:sample_index]

        sample_offset, sample_size =  getChunkOffset(stbl, sample_index)

        File.open ARGV[0], 'rb' do |file_input|
          file_input.seek(sample_offset, IO::SEEK_SET)
          sample_buffer = file_input.read(sample_size).unpack("C*")
          raise "wrong mp4 file format" unless sample_buffer.size == sample_size
          buffer = if stbl.stsd.vide
                     patchSampleBuffer(stbl, sample_index, sample_buffer)
                   else
                     patchAdtsBuffer(stbl, sample_buffer)
                   end

        end

        pts, dts = PESPacket.build_pts_dts stbl, sample_index
        pcr = params[:pid] == 256  ? dts * 300 : nil # please remember that PCR_PID is always 256

        random_access = isRandomAccessFrame(stbl, sample_index)

        remaining_size_for_payload = 188 - @offset

        padding = 0
        if remaining_size_for_payload > buffer.size
          # we need to add padding to adaptation field
          padding = remaining_size_for_payload - buffer.size
          # lets remove PES header length
          padding-= 9
          if pts
            padding-= 5
            padding-= 5 if pts != dts
          end
          padding = 0 if padding < 0
        end

        if random_access || pcr || padding > 0
          addAdaptationField random_access, pcr, padding
        end

        addPESHeader(pts, dts, buffer.size, stbl.stsd.vide)

        chunk = buffer.slice! 0, (188 - @offset) # here I rely on fact that if upper boundary of slice is higher than array size ruby will handle this properly :)
        chunk.each do|c|
          @packet[@offset] = c;@offset+=1
        end
        params[:buffer] = buffer
      else
        remaining_size_for_payload = 188 - @offset

        padding = 0
        if remaining_size_for_payload > buffer.size
          # we need to add padding to adaptation field
          padding = remaining_size_for_payload - buffer.size
        end
        if pcr || padding > 0
          addAdaptationField(false, pcr, padding)
        end
        chunk = buffer.slice! 0, (188 - @offset) # here I rely on fact that if upper boundary of slice is higher than array size ruby will handle this properly :)

        chunk.each do |c|
          @packet[@offset] = c;@offset+=1
        end

        params[:buffer] = buffer
      end
    end

  end

  def createPESPackets params

    params[:pusi] = true
    list = []
    while (item = PESPacket.new(params))
         list << item
         params[:cc]+= 1
         params[:cc]&= 0xFF
         params[:pusi] = false
         break if params[:buffer].empty?
    end
    list
  end

end

p "wrong parameter count. add mp4 file and output directory" and exit if ARGV.length == 0 or ARGV.length > 2
mediaFile = IsoBaseMediaFile.new
mediaFile.load(ARGV[0])



File.open (ARGV[1] ? ARGV[1] : 'result.ts') , 'wb' do |file|
  mpegts = MpegTs.new
  pat = mpegts.createProgramAssociationTable
  pms = mpegts.createProgramMapTable(mediaFile)

  pat.write(file)
  pms.write(file)

  video_presented = false
  audio_presented = false

  mediaFile.movieBox.traks.each{|trak|
    video_presented = true if trak.mdia.handler.handler_type == 'vide'
    audio_presented = true if trak.mdia.handler.handler_type == 'soun'
    break if video_presented && audio_presented
  }

  if video_presented and audio_presented
  #if false
    # lets find first video and audio traks
    audio_stbl = nil
    video_stbl = nil
    mediaFile.movieBox.traks.each{|trak|
      stbl = trak.mdia.minf.stbl
      next unless stbl.stsd.vide || stbl.stsd.soun
      video_stbl = stbl if stbl.stsd.vide
      audio_stbl = stbl if stbl.stsd.soun
      break if video_stbl and audio_stbl
    }

    audio_stbl_index = 0
    audio_сс = 0
    video_stbl_index = 0
    video_сс = 0
    while audio_stbl_index < audio_stbl.stsz.sample_sizes.size ||
          video_stbl_index < video_stbl.stsz.sample_sizes.size

      audio_pts,audio_dts = (audio_stbl_index < audio_stbl.stsz.sample_sizes.size()) ? MpegTs::PESPacket.build_pts_dts(audio_stbl, audio_stbl_index) : [-1, -1]
      vide_pts, video_dts = (video_stbl_index < video_stbl.stsz.sample_sizes.size()) ? MpegTs::PESPacket.build_pts_dts(video_stbl, video_stbl_index)  :[-1, -1]

      if audio_stbl_index == audio_stbl.stsz.sample_sizes.size || video_dts <= audio_dts
        mpegts.createPESPackets({pid: 256, cc:video_сс, sample_index:video_stbl_index, stbl:video_stbl}).each do |pes|
          pes.write(file)
          video_сс+=1
          video_сс&= 0xFF
        end
        video_stbl_index+=1
      else
        mpegts.createPESPackets({pid: 257, cc:audio_сс, sample_index:audio_stbl_index, stbl:audio_stbl}).each do |pes|
          pes.write(file)
          audio_сс+=1
          audio_сс&= 0xFF
        end
        audio_stbl_index+=1
      end
    end

  else
    # simple case when we have only audio or video trak
    mediaFile.movieBox.traks.each{|trak|
      stbl = trak.mdia.minf.stbl
      next unless stbl.stsd.vide || stbl.stsd.soun
      next if video_presented and !stbl.stsd.vide
      next if audio_presented and !stbl.stsd.soun
      cc = 00
      stbl.stsz.sample_sizes.size.times do |sample_index|

        mpegts.createPESPackets({pid: 256, cc:cc, sample_index:sample_index, stbl:stbl}).each do |pes|
          pes.write(file)
          cc+=1
          cc&= 0xFF
        end

      end

      break # lets process only one stream for now
    }
  end

end

