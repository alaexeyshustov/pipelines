module Orchestration
  module Executable
    # Implementors must define: .call(input, params = {}) -> Hash
    # input  - the resolved Hash from InputMappingResolver
    # params - the action's params Hash (may be empty)
  end
end
