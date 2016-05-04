class PatchPanel < Trema::Controller
  # superclass for patch-panel operation
  class PatchPanelError < StandardError; end
  # patch not found
  class PatchNotFoundError < PatchPanelError; end
  # patch already exists
  class PatchAlreadyExistsError < PatchPanelError; end
  # patch layer1/2 conflict
  class PatchLayerConflictError < PatchAlreadyExistsError; end
end