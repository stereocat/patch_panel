require 'link'

class WireLink < Link
  # logical wire (switch-internal port-to-port mapping rule)
  def initialize(dpid, port_a, port_b)
    @dpid_a = dpid
    @dpid_b = dpid
    @port_a = port_a
    @port_b = port_b
  end
end

class PatchData
  attr_reader :data

  # @param [Hash] data a patch data
  def initialize(data)
    @data = data
  end

  # @param [PatchData] other a patch object
  def layer_conflict?(other)
    (layer1wire? || other.layer1wire?) && equal_layer1(other)
  end

  def layer1wire?
    !layer2wire?
  end

  def layer2wire?
    @data.has_key?(:eth_src) || @data.has_key?(:eth_dst)
  end

  def ==(other)
    @data == other.data
  end

  private

  def equal_layer1(other)
    @data[:dpid] == other.data[:dpid] && @data[:inport] == other.data[:inport]
  end
end

class PatchPanelManager

  attr_reader :list

  def initialize
    @list = Array.new
  end

  # @param [Hash, PatchData] data a patch data
  def append(data)
    d = to_pp(data)
    @list.append(d)
    d.data
  end

  # @param [Hash, PatchData] data a patch data
  def delete(data)
    d = to_pp(data)
    @list.delete(d)
    d.data
  end

  # @param [Hash, PatchData] data a patch data
  def include?(data)
    @list.include?(to_pp(data))
  end

  # @param [Hash, PatchData] data a patch data
  def conflict_exists?(data)
    target = to_pp(data)
    @list.each do |item|
      return true if item.layer_conflict?(target)
    end
    false
  end

  # construct swiwtch-internal port-to-port mapping rule (logical wire)
  def logical_wires
    list = []
    @list.each do |flow|
      ports = flow.data[:outports] ? flow.data[:outports] : [flow.data[:outport]]
      ports.each do |port|
        wire_link = WireLink.new(flow.data[:dpid], flow.data[:inport], port)
        list.append(wire_link.to_hash.flatten)
      end
    end
    list.flatten
  end

  private

  def to_pp(data)
    case data
      when PatchData
        data
      when Hash
        PatchData.new(data)
      else
        nil # error
    end
  end
end
