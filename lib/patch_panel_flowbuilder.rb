require 'hashie'
require 'patch_panel_exceptions'

# Software patch-panel.
class PatchPanel < Trema::Controller
  private

  # @param [Hash,Hashie] target patch flow rules
  def build_priority(target)
    # default (MAX priority): 0xffff
    target.has_key?(:priority) ? target[:priority] : 0xffff
  end

  # @param [Hash,Hashie] target patch flow rules
  def build_match_condition(target)
    match_opt = Hash.new
    # Existance of :inport key is guaranteed by Grape API definition
    match_opt[:in_port] = target[:inport]
    # optional match key (Layer2 match key)
    if target.has_key?(:eth_src)
      match_opt[:source_mac_address] = target[:eth_src]
    end
    if target.has_key?(:eth_dst)
      match_opt[:destination_mac_address] = target[:eth_dst]
    end
    if target.has_key?(:vlan_vid)
      match_opt[:vlan_vid] = target[:vlan_vid]
    end
    puts "#match: #{match_opt.to_s}" # debug
    Match.new(match_opt)
  end

  # @param [Hash,Hashie] target patch flow rules
  def build_action_conditions(target)
    # Layer2 actions (if L2 match condition exists)
    # TODO: if specified only L2 action without eth_src/dst match conditions?
    actions = []
    if target.has_key?(:eth_src) || target.has_key?(:eth_dst)
      if target.has_key?(:set_vlan)
        puts "#actions append :set_vlan #{target[:set_vlan]}" # debug
        # (Pio/0.30.0) not exists Pio::OpenFlow13:: Actions for vlan tag operation
        # TODO: OpenFlow Protocol Version check
        actions.append Pio::OpenFlow10::SetVlanVid.new(target[:set_vlan])
      end
      if target.has_key?(:pop_vlan) && target[:pop_vlan]
        puts "#actions append :pop_vlan #{target[:pop_vlan]}" # debug
        actions.append Pio::OpenFlow10::StripVlanHeader.new
      end
    end

    # Layer1 actions
    ports = target.has_key?(:outports) ? target[:outports] : [target[:outport]]
    ports.each do |port|
      puts "#actions append SendOutPort #{port}"
      actions.append SendOutPort.new(port)
    end
    actions
  end
end

