import PlaygroundSupport
import MetalKit

// Create a device (checking for a compatible GPU)
guard let device = MTLCreateSystemDefaultDevice() else {
    fatalError("Metal is not supported on this device")
}

// setup view
let frame = CGRect(x: 0, y: 0, width: 600, height: 600)
let view = MTKView(frame: frame, device: device)
view.clearColor = MTLClearColor(red: 1, green: 1, blue: 0.8, alpha: 1)

// Setup model
// Allocator manages memory for the mesh data
let allocator = MTKMeshBufferAllocator(device: device)

// Model I/O creates a sphere with the specified size and returns a MDLMesh with all the vertex information in data buffers
let mdlMesh = MDLMesh(
    sphereWithExtent: [0.75, 0.75, 0.75],
    segments: [100, 100],
    inwardNormals: false,
    geometryType: .triangles,
    allocator: allocator)

// Convert from Model I/O mesh to a MetalKit mesh so Metal can use it
let mesh = try MTKMesh(mesh: mdlMesh, device: device)

// Command queue
guard let commandQueue = device.makeCommandQueue() else {
    fatalError("Could not create command queue")
}

// Normally shaders should be in a separate .metal file
let shader = """
#include <metal_stdlib>
using namespace metal;

struct VertexIn {
    float4 position [[attribute(0)]];
};

vertex float4 vertex_main(const VertexIn vertex_in [[stage_in]])
{
    return vertex_in.position;
}

fragment float4 fragment_main() {
    return float4(1, 0, 0, 1);
}
"""

// MARK: Library
// Setup a Metal library containing the shaders. The compiler will check these functions exist and make them available to a pipeline descriptor
let library = try device.makeLibrary(source: shader, options: nil)
let vertextFunction = library.makeFunction(name: "vertex_main")
let fragmentFunction = library.makeFunction(name: "fragment_main")

// MARK: Pipeline state
// Contains information the GPU needs, including the vertex and fragment functions created above
// By setting the state, the GPU thinks nothing will change until the state changes
// Pipeline state is created indirectly through a descriptor
let pipelineDescriptor = MTLRenderPipelineDescriptor()
pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
pipelineDescriptor.vertexFunction = vertextFunction
pipelineDescriptor.fragmentFunction = fragmentFunction

// MARK: Vertex descriptor
// Model I/O creates a vertex descriptor when the sphere mesh is loaded, so use that one
pipelineDescriptor.vertexDescriptor = MTKMetalVertexDescriptorFromModelIO(mesh.vertexDescriptor)

// Create pipeline state from the descriptor
// Creating a pipeline state is expensive, so only do it once.
// In a proper app it's common to create several pipeline states that call different shading functions or different vertex layouts
let pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)

// MARK: Rendering
// From this point on, the code is performed every frame
// It's common to perform many render passes on each frame

// Create command buffer to store all the commands that will be done
guard let commandBuffer = commandQueue.makeCommandBuffer(),
      // Obtain a reference to the view's render pass descriptor
      let renderPassDescriptor = view.currentRenderPassDescriptor,
      // Obtain a render command encoder from the render pass descriptor
      let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
else {
    fatalError()
}

// Gives pipeline state to the render encoder
renderEncoder.setRenderPipelineState(pipelineState)

// Gives vertex buffer to the render encoder.
// Offset is where the vertex info starts
// Index is how the the GPU vertex shader locates the buffer
renderEncoder.setVertexBuffer(mesh.vertexBuffers[0].buffer, offset: 0, index: 0)

// MARK: Submeshes
// This sphere only has one submesh...
guard let submesh = mesh.submeshes.first else {
    fatalError()
}

// MARK: Draw call
// Instruct GPU to render a vertex buffer with triangles in the order based on the submesh index info
renderEncoder.drawIndexedPrimitives(
    type: .triangle,
    indexCount: submesh.indexCount,
    indexType: submesh.indexType,
    indexBuffer: submesh.indexBuffer.buffer,
    indexBufferOffset: 0)

// State that there are no more draw calls and mark the end of the render pass
renderEncoder.endEncoding()
// Get the drawable from the MTKView
guard let drawable = view.currentDrawable else {
    fatalError()
}
// Send the command to diplay to the GPU
commandBuffer.present(drawable)
commandBuffer.commit()

// Set playground live view
PlaygroundPage.current.liveView = view
