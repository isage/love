/**
 * Copyright (c) 2006-2020 LOVE Development Team
 *
 * This software is provided 'as-is', without any express or implied
 * warranty.  In no event will the authors be held liable for any damages
 * arising from the use of this software.
 *
 * Permission is granted to anyone to use this software for any purpose,
 * including commercial applications, and to alter it and redistribute it
 * freely, subject to the following restrictions:
 *
 * 1. The origin of this software must not be misrepresented; you must not
 *    claim that you wrote the original software. If you use this software
 *    in a product, an acknowledgment in the product documentation would be
 *    appreciated but is not required.
 * 2. Altered source versions must be plainly marked as such, and must not be
 *    misrepresented as being the original software.
 * 3. This notice may not be removed or altered from any source distribution.
 **/

#include "Graphics.h"
#include "StreamBuffer.h"
#include "Buffer.h"
#include "Texture.h"
#include "Shader.h"
#include "window/Window.h"
#include "image/Image.h"

#import <QuartzCore/CAMetalLayer.h>

namespace love
{
namespace graphics
{
namespace metal
{

static MTLSamplerMinMagFilter getMTLSamplerFilter(SamplerState::FilterMode mode)
{
	switch (mode)
	{
		case SamplerState::FILTER_LINEAR: return MTLSamplerMinMagFilterLinear;
		case SamplerState::FILTER_NEAREST: return MTLSamplerMinMagFilterNearest;
		case SamplerState::FILTER_MAX_ENUM: return MTLSamplerMinMagFilterLinear;
	}
	return MTLSamplerMinMagFilterLinear;
}

static MTLSamplerMipFilter getMTLSamplerMipFilter(SamplerState::MipmapFilterMode mode)
{
	switch (mode)
	{
		case SamplerState::MIPMAP_FILTER_NONE: return MTLSamplerMipFilterNotMipmapped;
		case SamplerState::MIPMAP_FILTER_LINEAR: return MTLSamplerMipFilterLinear;
		case SamplerState::MIPMAP_FILTER_NEAREST: return MTLSamplerMipFilterNearest;
		case SamplerState::MIPMAP_FILTER_MAX_ENUM: return MTLSamplerMipFilterNotMipmapped;
	}
	return MTLSamplerMipFilterNotMipmapped;
}

static MTLSamplerAddressMode getMTLSamplerAddressMode(SamplerState::WrapMode mode)
{
	switch (mode)
	{
		case SamplerState::WRAP_CLAMP: return MTLSamplerAddressModeClampToEdge;
		case SamplerState::WRAP_CLAMP_ZERO: return MTLSamplerAddressModeClampToZero;
#ifdef LOVE_MACOS
		case SamplerState::WRAP_CLAMP_ONE: return MTLSamplerAddressModeClampToBorderColor;
#else
		case SamplerState::WRAP_CLAMP_ONE: return MTLSamplerAddressModeClampToZero;
#endif
		case SamplerState::WRAP_REPEAT: return MTLSamplerAddressModeRepeat;
		case SamplerState::WRAP_MIRRORED_REPEAT: return MTLSamplerAddressModeMirrorRepeat;
		case SamplerState::WRAP_MAX_ENUM: return MTLSamplerAddressModeClampToEdge;
	}
	return MTLSamplerAddressModeClampToEdge;
}

static MTLCompareFunction getMTLCompareFunction(CompareMode mode)
{
	switch (mode)
	{
		case COMPARE_LESS: return MTLCompareFunctionLess;
		case COMPARE_LEQUAL: return MTLCompareFunctionLessEqual;
		case COMPARE_EQUAL: return MTLCompareFunctionEqual;
		case COMPARE_GEQUAL: return MTLCompareFunctionGreaterEqual;
		case COMPARE_GREATER: return MTLCompareFunctionGreater;
		case COMPARE_NOTEQUAL: return MTLCompareFunctionNotEqual;
		case COMPARE_ALWAYS: return MTLCompareFunctionAlways;
		case COMPARE_NEVER: return MTLCompareFunctionNever;
		case COMPARE_MAX_ENUM: return MTLCompareFunctionNever;
	}
	return MTLCompareFunctionNever;
}

static MTLVertexFormat getMTLVertexFormat(vertex::DataType type, int components)
{
	// TODO
	return MTLVertexFormatFloat4;
}

static MTLBlendOperation getMTLBlendOperation(BlendOperation op)
{
	switch (op)
	{
		case BLENDOP_ADD: return MTLBlendOperationAdd;
		case BLENDOP_SUBTRACT: return MTLBlendOperationSubtract;
		case BLENDOP_REVERSE_SUBTRACT: return MTLBlendOperationReverseSubtract;
		case BLENDOP_MIN: return MTLBlendOperationMin;
		case BLENDOP_MAX: return MTLBlendOperationMax;
		case BLENDOP_MAX_ENUM: return MTLBlendOperationAdd;
	}
	return MTLBlendOperationAdd;
}

static MTLBlendFactor getMTLBlendFactor(BlendFactor factor)
{
	switch (factor)
	{
		case BLENDFACTOR_ZERO: return MTLBlendFactorZero;
		case BLENDFACTOR_ONE: return MTLBlendFactorOne;
		case BLENDFACTOR_SRC_COLOR: return MTLBlendFactorSourceColor;
		case BLENDFACTOR_ONE_MINUS_SRC_COLOR: return MTLBlendFactorOneMinusSourceColor;
		case BLENDFACTOR_SRC_ALPHA: return MTLBlendFactorSourceAlpha;
		case BLENDFACTOR_ONE_MINUS_SRC_ALPHA: return MTLBlendFactorOneMinusSourceAlpha;
		case BLENDFACTOR_DST_COLOR: return MTLBlendFactorDestinationColor;
		case BLENDFACTOR_ONE_MINUS_DST_COLOR: return MTLBlendFactorOneMinusDestinationColor;
		case BLENDFACTOR_DST_ALPHA: return MTLBlendFactorDestinationAlpha;
		case BLENDFACTOR_ONE_MINUS_DST_ALPHA: return MTLBlendFactorOneMinusDestinationAlpha;
		case BLENDFACTOR_SRC_ALPHA_SATURATED: return MTLBlendFactorSourceAlphaSaturated;
		case BLENDFACTOR_MAX_ENUM: return MTLBlendFactorZero;
	}
	return MTLBlendFactorZero;
}

love::graphics::Graphics *createInstance()
{
	love::graphics::Graphics *instance = nullptr;

	try
	{
		instance = new Graphics();
	}
	catch (love::Exception &e)
	{
		printf("Cannot create Metal renderer: %s\n", e.what());
	}

	return instance;
}

Graphics::Graphics()
	: device(nil)
	, commandQueue(nil)
	, commandBuffer(nil)
	, renderEncoder(nil)
	, blitEncoder(nil)
	, metalLayer(nil)
	, activeDrawable(nil)
	, passDesc(nil)
	, dirtyRenderState(STATEBIT_ALL)
	, windowHasStencil(false)
{ @autoreleasepool {
	device = MTLCreateSystemDefaultDevice();
	if (device == nil)
		throw love::Exception("Metal is not supported on this system.");

	commandQueue = [device newCommandQueue];
	passDesc = [MTLRenderPassDescriptor renderPassDescriptor];

	initCapabilities();

	auto window = Module::getInstance<love::window::Window>(M_WINDOW);

	if (window != nullptr)
	{
		window->setGraphics(this);

		if (window->isOpen())
		{
			int w, h;
			love::window::WindowSettings settings;
			window->getWindow(w, h, settings);

			double dpiW = w;
			double dpiH = h;
			window->windowToDPICoords(&dpiW, &dpiH);

			void *context = nullptr; // TODO
			setMode(context, (int) dpiW, (int) dpiH, window->getPixelWidth(), window->getPixelHeight(), settings.stencil);
		}
	}
}}

Graphics::~Graphics()
{ @autoreleasepool {
	submitCommandBuffer();
	passDesc = nil;
	commandQueue = nil;
	device = nil;
}}

love::graphics::StreamBuffer *Graphics::newStreamBuffer(BufferType type, size_t size)
{
	return CreateStreamBuffer(device, type, size);
}

love::graphics::Texture *Graphics::newTexture(const Texture::Settings &settings, const Texture::Slices *data)
{
	return new Texture(device, settings, data);
}

love::graphics::ShaderStage *Graphics::newShaderStageInternal(ShaderStage::StageType stage, const std::string &cachekey, const std::string &source, bool gles)
{
	return nullptr; // TODO: new ShaderStage(this, stage, source, gles, cachekey);
}

love::graphics::Shader *Graphics::newShaderInternal(love::graphics::ShaderStage *vertex, love::graphics::ShaderStage *pixel)
{
	return new Shader(vertex, pixel);
}

love::graphics::Buffer *Graphics::newBuffer(size_t size, const void *data, BufferType type, vertex::Usage usage, uint32 mapflags)
{
	return new Buffer(device, size, data, type, usage, mapflags);
}

void Graphics::setViewportSize(int width, int height, int pixelwidth, int pixelheight)
{
	this->width = width;
	this->height = height;
	this->pixelWidth = pixelwidth;
	this->pixelHeight = pixelheight;

	if (!isRenderTargetActive())
	{
		dirtyRenderState |= STATEBIT_VIEWPORT | STATEBIT_SCISSOR;

		// Set up the projection matrix
		projectionMatrix = Matrix4::ortho(0.0, (float) width, (float) height, 0.0, -10.0f, 10.0f);
	}
}

bool Graphics::setMode(void *context, int width, int height, int pixelwidth, int pixelheight, bool windowhasstencil)
{ @autoreleasepool {
	this->width = width;
	this->height = height;
	this->metalLayer = (__bridge CAMetalLayer *) context;

	this->windowHasStencil = windowhasstencil;

	metalLayer.device = device;

	setViewportSize(width, height, pixelwidth, pixelheight);

	created = true;

	if (batchedDrawState.vb[0] == nullptr)
	{
		// Initial sizes that should be good enough for most cases. It will
		// resize to fit if needed, later.
		batchedDrawState.vb[0] = CreateStreamBuffer(device, BUFFER_VERTEX, 1024 * 1024 * 1);
		batchedDrawState.vb[1] = CreateStreamBuffer(device, BUFFER_VERTEX, 256  * 1024 * 1);
		batchedDrawState.indexBuffer = CreateStreamBuffer(device, BUFFER_INDEX, sizeof(uint16) * LOVE_UINT16_MAX);
	}

	createQuadIndexBuffer();

	// Restore the graphics state.
	restoreState(states.back());

	int gammacorrect = isGammaCorrect() ? 1 : 0;
	Shader::Language target = getShaderLanguageTarget();

	// We always need a default shader.
	for (int i = 0; i < Shader::STANDARD_MAX_ENUM; i++)
	{
		if (!Shader::standardShaders[i])
		{
			const auto &code = defaultShaderCode[i][target][gammacorrect];
//			Shader::standardShaders[i] = love::graphics::Graphics::newShader(code.source[ShaderStage::STAGE_VERTEX], code.source[ShaderStage::STAGE_PIXEL]);
		}
	}

	// A shader should always be active, but the default shader shouldn't be
	// returned by getShader(), so we don't do setShader(defaultShader).
//	if (!Shader::current)
//		Shader::standardShaders[Shader::STANDARD_DEFAULT]->attach();

	return true;
}}

void Graphics::unSetMode()
{ @autoreleasepool {
	if (!isCreated())
		return;

	flushBatchedDraws();

	submitCommandBuffer();

	for (auto temp : temporaryTextures)
		temp.texture->release();

	temporaryTextures.clear();

	created = false;
	metalLayer = nil;
	activeDrawable = nil;
}}

void Graphics::setActive(bool enable)
{
	flushBatchedDraws();
	active = enable;
}

id<MTLCommandBuffer> Graphics::useCommandBuffer()
{
	if (commandBuffer == nil)
		commandBuffer = [commandQueue commandBuffer];

	return commandBuffer;
}

void Graphics::submitCommandBuffer()
{
	submitRenderEncoder();
	submitBlitEncoder();

	if (commandBuffer != nil)
	{
		[commandBuffer commit];
		commandBuffer = nil;
	}
}

id<MTLRenderCommandEncoder> Graphics::useRenderEncoder()
{
	if (renderEncoder == nil)
	{
		submitBlitEncoder();

		const auto &rts = states.back().renderTargets;
		if (rts.getFirstTarget().texture.get() != nullptr)
		{

		}
		else
		{
			if (activeDrawable == nil)
				activeDrawable = [metalLayer nextDrawable];
			passDesc.colorAttachments[0].texture = activeDrawable.texture;
		}

		renderEncoder = [useCommandBuffer() renderCommandEncoderWithDescriptor:passDesc];
		dirtyRenderState = STATEBIT_ALL;
	}

	return renderEncoder;
}

void Graphics::submitRenderEncoder()
{
	if (renderEncoder != nil)
	{
		[renderEncoder endEncoding];
		renderEncoder = nil;

		passDesc.colorAttachments[0].texture = nil;
	}
}

id<MTLBlitCommandEncoder> Graphics::useBlitEncoder()
{
	if (blitEncoder == nil)
	{
		submitRenderEncoder();
		blitEncoder = [useCommandBuffer() blitCommandEncoder];
	}

	return blitEncoder;
}

void Graphics::submitBlitEncoder()
{
	if (blitEncoder != nil)
	{
		[blitEncoder endEncoding];
		blitEncoder = nil;
	}
}

id<MTLSamplerState> Graphics::getCachedSampler(const SamplerState &s)
{ @autoreleasepool {
	id<MTLSamplerState> sampler = nil;

	{
		MTLSamplerDescriptor *desc = [MTLSamplerDescriptor new];

		desc.minFilter = getMTLSamplerFilter(s.minFilter);
		desc.magFilter = getMTLSamplerFilter(s.magFilter);
		desc.mipFilter = getMTLSamplerMipFilter(s.mipmapFilter);
		desc.maxAnisotropy = std::max(1.0f, std::min((float)s.maxAnisotropy, 16.0f));

		desc.sAddressMode = getMTLSamplerAddressMode(s.wrapU);
		desc.tAddressMode = getMTLSamplerAddressMode(s.wrapV);
		desc.rAddressMode = getMTLSamplerAddressMode(s.wrapW);

#ifdef LOVE_MACOS
		desc.borderColor = MTLSamplerBorderColorOpaqueWhite;
#endif

		desc.lodMinClamp = s.minLod;
		desc.lodMaxClamp = s.maxLod;

		if (s.depthSampleMode.hasValue)
			desc.compareFunction = getMTLCompareFunction(s.depthSampleMode.value);

		sampler = [device newSamplerStateWithDescriptor:desc];
	}

	return sampler;
}}

id<MTLRenderPipelineState> Graphics::getCachedRenderPipelineState(const PipelineState &state)
{
	MTLRenderPipelineDescriptor *pipedesc = [MTLRenderPipelineDescriptor new];

	MTLVertexDescriptor *vertdesc = [MTLVertexDescriptor vertexDescriptor];

	const auto &attributes = state.vertexAttributes;
	uint32 allbits = attributes.enableBits;
	uint32 i = 0;
	while (allbits)
	{
		uint32 bit = 1u << i;

		if (attributes.enableBits & bit)
		{
			const auto &attrib = attributes.attribs[i];

			vertdesc.attributes[i].format = getMTLVertexFormat(attrib.type, attrib.components);
			vertdesc.attributes[i].offset = attrib.offsetFromVertex;
			vertdesc.attributes[i].bufferIndex = attrib.bufferIndex;

			const auto &layout = attributes.bufferLayouts[attrib.bufferIndex];

			bool instanced = attributes.instanceBits & (1u << attrib.bufferIndex);
			auto step = instanced ? MTLVertexStepFunctionPerInstance : MTLVertexStepFunctionPerVertex;

			vertdesc.layouts[attrib.bufferIndex].stride = layout.stride;
			vertdesc.layouts[attrib.bufferIndex].stepFunction = step;
		}

		i++;
		allbits >>= 1;
	}

	pipedesc.vertexDescriptor = vertdesc;

//	pipedesc.

	NSError *err = nil;
	id<MTLRenderPipelineState> pipestate = [device newRenderPipelineStateWithDescriptor:pipedesc error:&err];

	return pipestate;
}

id<MTLDepthStencilState> Graphics::getCachedDepthStencilState(const DepthState &depth, const StencilState &stencil)
{
	id<MTLDepthStencilState> state = nil;

	{
		MTLStencilDescriptor *stencildesc = [MTLStencilDescriptor new];

		stencildesc.stencilCompareFunction = getMTLCompareFunction(stencil.compare);
		stencildesc.stencilFailureOperation = MTLStencilOperationKeep;
		stencildesc.depthFailureOperation = MTLStencilOperationKeep;
		stencildesc.depthStencilPassOperation = MTLStencilOperationKeep; // TODO
		stencildesc.readMask = stencil.readMask;
		stencildesc.writeMask = stencil.writeMask;

		MTLDepthStencilDescriptor *desc = [MTLDepthStencilDescriptor new];

		desc.depthCompareFunction = getMTLCompareFunction(depth.compare);
		desc.depthWriteEnabled = depth.write;
		desc.frontFaceStencil = stencildesc;
		desc.backFaceStencil = stencildesc;

		state = [device newDepthStencilStateWithDescriptor:desc];
	}

	return state;
}

void Graphics::applyRenderState(id<MTLRenderCommandEncoder> encoder)
{
	const uint32 pipelineStateBits = STATEBIT_SHADER | STATEBIT_BLEND | STATEBIT_COLORMASK;

	uint32 dirtyState = dirtyRenderState;
	const auto &state = states.back();

	if (dirtyState & (STATEBIT_VIEWPORT | STATEBIT_SCISSOR))
	{
		int rtw = 0;
		int rth = 0;

		const auto &rt = state.renderTargets.getFirstTarget();
		if (rt.texture.get())
		{
			rtw = rt.texture->getPixelWidth();
			rth = rt.texture->getPixelHeight();
		}
		else
		{
			rtw = getPixelWidth();
			rth = getPixelHeight();
		}

		if (dirtyState & STATEBIT_VIEWPORT)
		{
			MTLViewport view;
			view.originX = 0.0;
			view.originY = 0.0;
			view.width = rtw;
			view.height = rth;
			view.znear = 0.0;
			view.zfar = 1.0;
			[encoder setViewport:view];
		}

		MTLScissorRect rect = {0, 0, (NSUInteger)rtw, (NSUInteger)rth};

		if (state.scissor)
		{
			// TODO: clamping
			double dpiscale = getCurrentDPIScale();
			rect.x = (NSUInteger)(state.scissorRect.x*dpiscale);
			rect.y = (NSUInteger)(state.scissorRect.y*dpiscale);
			rect.width = (NSUInteger)(state.scissorRect.w*dpiscale);
			rect.height = (NSUInteger)(state.scissorRect.h*dpiscale);
		}

		[encoder setScissorRect:rect];
	}

	if (dirtyState & STATEBIT_FACEWINDING)
	{
		auto winding = state.winding == vertex::WINDING_CCW ? MTLWindingCounterClockwise : MTLWindingClockwise;
		[encoder setFrontFacingWinding:winding];
	}

	if (dirtyState & STATEBIT_WIREFRAME)
	{
		auto mode = state.wireframe ? MTLTriangleFillModeLines : MTLTriangleFillModeFill;
		[encoder setTriangleFillMode:mode];
	}

	if (dirtyState & STATEBIT_CULLMODE)
	{
		// TODO
	}

	// TODO: attributes
	if (dirtyState & pipelineStateBits)
	{
		if (dirtyState & STATEBIT_BLEND)
		{

		}

		if (dirtyState & STATEBIT_SHADER)
		{

		}

		if (dirtyState & STATEBIT_COLORMASK)
		{

		}
	}

	if (dirtyState & (STATEBIT_DEPTH | STATEBIT_STENCIL))
	{
//		id<MTLDepthStencilState> dsstate = getCachedDepthStencilState(<#const DepthState &depth#>, <#const StencilState &stencil#>)
	}

	dirtyRenderState = 0;
}

void Graphics::draw(const DrawCommand &cmd)
{ @autoreleasepool {
	id<MTLRenderCommandEncoder> encoder = useRenderEncoder();

	applyRenderState(encoder);

	// TODO: vertex attributes

	id<MTLTexture> texture = (__bridge id<MTLTexture>)(void *) cmd.texture->getHandle();
	[encoder setFragmentTexture:texture atIndex:0];

	[encoder setCullMode:MTLCullModeNone];

	[encoder drawPrimitives:MTLPrimitiveTypeTriangle
				vertexStart:cmd.vertexStart
				vertexCount:cmd.vertexCount
			  instanceCount:cmd.instanceCount];
}}

void Graphics::draw(const DrawIndexedCommand &cmd)
{ @autoreleasepool {
	id<MTLRenderCommandEncoder> encoder = useRenderEncoder();

	applyRenderState(encoder);

	id<MTLTexture> texture = (__bridge id<MTLTexture>)(void *) cmd.texture->getHandle();
	[encoder setFragmentTexture:texture atIndex:0];

	[encoder setCullMode:MTLCullModeNone];

	auto indexType = cmd.indexType == INDEX_UINT32 ? MTLIndexTypeUInt32 : MTLIndexTypeUInt16;

	[encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
						indexCount:cmd.indexCount
						 indexType:indexType
					   indexBuffer:(__bridge id<MTLBuffer>)(void*)cmd.indexBuffer->getHandle()
				 indexBufferOffset:cmd.indexBufferOffset
					 instanceCount:cmd.instanceCount];
}}

void Graphics::drawQuads(int start, int count, const vertex::Attributes &attributes, const vertex::BufferBindings &buffers, love::graphics::Texture *texture)
{ @autoreleasepool {
	const int MAX_VERTICES_PER_DRAW = LOVE_UINT16_MAX;
	const int MAX_QUADS_PER_DRAW    = MAX_VERTICES_PER_DRAW / 4;

	id<MTLRenderCommandEncoder> encoder = useRenderEncoder();

	applyRenderState(encoder);

	id<MTLTexture> tex = (__bridge id<MTLTexture>)(void *) texture->getHandle();
	[encoder setFragmentTexture:tex atIndex:0];

	[encoder setCullMode:MTLCullModeNone];

	id<MTLBuffer> ib = (__bridge id<MTLBuffer>)(void *) quadIndexBuffer->getHandle();

	// TODO: Set vertex buffers/attributes
	// TODO: support for iOS devices that don't support base vertex.

	int basevertex = start * 4;

	for (int quadindex = 0; quadindex < count; quadindex += MAX_QUADS_PER_DRAW)
	{
		int quadcount = std::min(MAX_QUADS_PER_DRAW, count - quadindex);

		[encoder drawIndexedPrimitives:MTLPrimitiveTypeTriangle
							indexCount:quadcount * 6
							 indexType:MTLIndexTypeUInt16
						   indexBuffer:ib
					 indexBufferOffset:0
						 instanceCount:1
							baseVertex:basevertex
						  baseInstance:0];

		++drawCalls;

		basevertex += quadcount * 4;
	}
}}

void Graphics::setRenderTargetsInternal(const RenderTargets &rts, int w, int h, int pixelw, int pixelh, bool hasSRGBcanvas)
{ @autoreleasepool {
	const DisplayState &state = states.back();

	endPass();

	for (size_t i = 0; i < rts.colors.size(); i++)
	{
		auto rt = rts.colors[i];
		auto tex = rt.texture;
		auto desc = passDesc.colorAttachments[i];

		desc.texture = (__bridge id<MTLTexture>)(void*)tex->getRenderTargetHandle();
		desc.level = rt.mipmap;

		if (tex->getTextureType() == TEXTURE_VOLUME)
		{
			desc.slice = 0;
			desc.depthPlane = rt.slice;
		}
		else
		{
			desc.slice = rt.slice;
			desc.depthPlane = 0;
		}

		// Default to load until clear or discard is called.
		desc.loadAction = MTLLoadActionLoad;
		desc.storeAction = MTLStoreActionStore;

		desc.resolveTexture = nil;

		if (tex->getMSAA() > 1)
		{
			// TODO
			desc.resolveTexture = (__bridge id<MTLTexture>)(void*)tex->getHandle();

			// TODO: This StoreAction is only supported sometimes.
			desc.storeAction = MTLStoreActionStoreAndMultisampleResolve;
		}

		passDesc.colorAttachments[i] = desc;
	}

	for (size_t i = rts.colors.size(); i < MAX_COLOR_RENDER_TARGETS; i++)
		passDesc.colorAttachments[i] = nil;

	// TODO: depth/stencil attachments
	// TODO: projection matrix
	// TODO: backbuffer
	dirtyRenderState = STATEBIT_ALL;
}}

void Graphics::endPass()
{
	auto &rts = states.back().renderTargets;
	love::graphics::Texture *depthstencil = rts.depthStencil.texture.get();

	// Discard the depth/stencil buffer if we're using an internal cached one.
	if (depthstencil == nullptr && (rts.temporaryRTFlags & (TEMPORARY_RT_DEPTH | TEMPORARY_RT_STENCIL)) != 0)
		discard({}, true);

	// Resolve MSAA buffers. MSAA is only supported for 2D render targets so we
	// don't have to worry about resolving to slices.
	if (rts.colors.size() > 0 && rts.colors[0].texture->getMSAA() > 1)
	{
		int mip = rts.colors[0].mipmap;
		int w = rts.colors[0].texture->getPixelWidth(mip);
		int h = rts.colors[0].texture->getPixelHeight(mip);

		for (int i = 0; i < (int) rts.colors.size(); i++)
		{
			Texture *c = (Texture *) rts.colors[i].texture.get();

			if (!c->isReadable())
				continue;

			// TODO
		}
	}

	if (depthstencil != nullptr && depthstencil->getMSAA() > 1 && depthstencil->isReadable())
	{
		// TODO
	}

	for (const auto &rt : rts.colors)
	{
		if (rt.texture->getMipmapsMode() == Texture::MIPMAPS_AUTO && rt.mipmap == 0)
			rt.texture->generateMipmaps();
	}

	int dsmipmap = rts.depthStencil.mipmap;
	if (depthstencil != nullptr && depthstencil->getMipmapsMode() == Texture::MIPMAPS_AUTO && dsmipmap == 0)
		depthstencil->generateMipmaps();
}

void Graphics::clear(OptionalColorf c, OptionalInt stencil, OptionalDouble depth)
{
	if (c.hasValue || stencil.hasValue || depth.hasValue)
		flushBatchedDraws();

	// TODO
}

void Graphics::clear(const std::vector<OptionalColorf> &colors, OptionalInt stencil, OptionalDouble depth)
{
	if (colors.size() == 0 && !stencil.hasValue && !depth.hasValue)
		return;

	int ncolorcanvases = (int) states.back().renderTargets.colors.size();
	int ncolors = (int) colors.size();

	if (ncolors <= 1 && ncolorcanvases <= 1)
	{
		clear(ncolors > 0 ? colors[0] : OptionalColorf(), stencil, depth);
		return;
	}

	flushBatchedDraws();

	// TODO
}

void Graphics::discard(const std::vector<bool> &colorbuffers, bool depthstencil)
{
	flushBatchedDraws();
	// TODO
}

void Graphics::present(void *screenshotCallbackData)
{ @autoreleasepool {
	if (!isActive())
		return;

	if (isRenderTargetActive())
		throw love::Exception("present cannot be called while a render target is active.");

	deprecations.draw(this);

	endPass();

	if (!pendingScreenshotCallbacks.empty())
	{
		int w = getPixelWidth();
		int h = getPixelHeight();

		size_t row = 4 * w;
		size_t size = row * h;

		uint8 *screenshot = nullptr;

		try
		{
			screenshot = new uint8[size];
		}
		catch (std::exception &)
		{
			delete[] screenshot;
			throw love::Exception("Out of memory.");
		}

		// TODO

		// Replace alpha values with full opacity.
		for (size_t i = 3; i < size; i += 4)
			screenshot[i] = 255;

		auto imagemodule = Module::getInstance<love::image::Image>(M_IMAGE);

		for (int i = 0; i < (int) pendingScreenshotCallbacks.size(); i++)
		{
			const auto &info = pendingScreenshotCallbacks[i];
			image::ImageData *img = nullptr;

			try
			{
				img = imagemodule->newImageData(w, h, PIXELFORMAT_RGBA8_UNORM, screenshot);
			}
			catch (love::Exception &)
			{
				delete[] screenshot;
				info.callback(&info, nullptr, nullptr);
				for (int j = i + 1; j < (int) pendingScreenshotCallbacks.size(); j++)
				{
					const auto &ninfo = pendingScreenshotCallbacks[j];
					ninfo.callback(&ninfo, nullptr, nullptr);
				}
				pendingScreenshotCallbacks.clear();
				throw;
			}

			info.callback(&info, img, screenshotCallbackData);
			img->release();
		}

		delete[] screenshot;
		pendingScreenshotCallbacks.clear();
	}

	for (StreamBuffer *buffer : batchedDrawState.vb)
		buffer->nextFrame();
	batchedDrawState.indexBuffer->nextFrame();

	id<MTLCommandBuffer> cmd = getCommandBuffer();

	if (cmd != nil && activeDrawable != nil)
		[cmd presentDrawable:activeDrawable];

	submitCommandBuffer();

	auto window = Module::getInstance<love::window::Window>(M_WINDOW);
	if (window != nullptr)
		window->swapBuffers();

	activeDrawable = nil;

	// Reset the per-frame stat counts.
	drawCalls = 0;
	//gl.stats.shaderSwitches = 0;
	renderTargetSwitchCount = 0;
	drawCallsBatched = 0;

	// This assumes temporary canvases will only be used within a render pass.
	for (int i = (int) temporaryTextures.size() - 1; i >= 0; i--)
	{
		if (temporaryTextures[i].framesSinceUse >= MAX_TEMPORARY_TEXTURE_UNUSED_FRAMES)
		{
			temporaryTextures[i].texture->release();
			temporaryTextures[i] = temporaryTextures.back();
			temporaryTextures.pop_back();
		}
		else
			temporaryTextures[i].framesSinceUse++;
	}
}}

void Graphics::setColor(Colorf c)
{
	// TODO
}

void Graphics::setScissor(const Rect &rect)
{
	flushBatchedDraws();

	DisplayState &state = states.back();
	state.scissor = true;
	state.scissorRect = rect;
	dirtyRenderState |= STATEBIT_SCISSOR;
}

void Graphics::setScissor()
{
	DisplayState &state = states.back();
	if (state.scissor)
	{
		flushBatchedDraws();
		state.scissor = false;
		dirtyRenderState |= STATEBIT_SCISSOR;
	}
}

void Graphics::drawToStencilBuffer(StencilAction action, int value)
{
	const auto &rts = states.back().renderTargets;
	love::graphics::Texture *dstexture = rts.depthStencil.texture.get();

	if (!isRenderTargetActive() && !windowHasStencil)
		throw love::Exception("The window must have stenciling enabled to draw to the main screen's stencil buffer.");
	else if (isRenderTargetActive() && (rts.temporaryRTFlags & TEMPORARY_RT_STENCIL) == 0 && (dstexture == nullptr || !isPixelFormatStencil(dstexture->getPixelFormat())))
		throw love::Exception("Drawing to the stencil buffer with a Canvas active requires either stencil=true or a custom stencil-type Canvas to be used, in setCanvas.");

	flushBatchedDraws();

	writingToStencil = true;

	dirtyRenderState |= STATEBIT_STENCIL;
	// TODO
}

void Graphics::stopDrawToStencilBuffer()
{
	if (!writingToStencil)
		return;

	flushBatchedDraws();

	writingToStencil = false;

	const DisplayState &state = states.back();

	// Revert the color write mask.
	setColorMask(state.colorMask);

	// Use the user-set stencil test state when writes are disabled.
	setStencilTest(state.stencilCompare, state.stencilTestValue);

	dirtyRenderState |= STATEBIT_STENCIL;
}

void Graphics::setStencilTest(CompareMode compare, int value)
{
	// TODO
}

void Graphics::setDepthMode(CompareMode compare, bool write)
{
	// TODO
}

void Graphics::setFrontFaceWinding(vertex::Winding winding)
{
	// TODO
}

void Graphics::setColorMask(ColorChannelMask mask)
{
	// TODO
}

void Graphics::setBlendState(const BlendState &blend)
{
	if (!(blend == states.back().blend))
	{
		flushBatchedDraws();
		states.back().blend = blend;
		dirtyRenderState |= STATEBIT_BLEND;
	}
}

void Graphics::setPointSize(float size)
{
	// TODO
}

void Graphics::setWireframe(bool enable)
{
	// TODO
}

PixelFormat Graphics::getSizedFormat(PixelFormat format, bool /*rendertarget*/, bool /*readable*/, bool /*sRGB*/) const
{
	switch (format)
	{
	case PIXELFORMAT_NORMAL:
		if (isGammaCorrect())
			return PIXELFORMAT_sRGBA8_UNORM;
		else
			return PIXELFORMAT_RGBA8_UNORM;
	case PIXELFORMAT_HDR:
		return PIXELFORMAT_RGBA16_FLOAT;
	default:
		return format;
	}
}

bool Graphics::isPixelFormatSupported(PixelFormat format, bool rendertarget, bool readable, bool sRGB)
{
	return true; // TODO
}

Graphics::Renderer Graphics::getRenderer() const
{
	return RENDERER_METAL;
}

bool Graphics::usesGLSLES() const
{
#ifdef LOVE_IOS
	return true;
#else
	return false;
#endif
}

Graphics::RendererInfo Graphics::getRendererInfo() const
{
	RendererInfo info;
	info.name = "Metal";
	info.version = "1"; // TODO
	info.vendor = ""; // TODO
	info.device = device.name.UTF8String;
	return info;
}

Shader::Language Graphics::getShaderLanguageTarget() const
{
	return usesGLSLES() ? Shader::LANGUAGE_ESSL3 : Shader::LANGUAGE_GLSL3;
}

void Graphics::initCapabilities()
{
	int msaa = 1;
	const int checkmsaa[] = {32, 16, 8, 4, 2};
	for (int samples : checkmsaa)
	{
		if ([device supportsTextureSampleCount:samples])
		{
			msaa = samples;
			break;
		}
	}

	capabilities.features[FEATURE_MULTI_RENDER_TARGET_FORMATS] = true;
	capabilities.features[FEATURE_CLAMP_ZERO] = true;
	capabilities.features[FEATURE_BLEND_MINMAX] = true;
	capabilities.features[FEATURE_LIGHTEN] = true;
	capabilities.features[FEATURE_FULL_NPOT] = true;
	capabilities.features[FEATURE_PIXEL_SHADER_HIGHP] = true;
	capabilities.features[FEATURE_SHADER_DERIVATIVES] = true;
	capabilities.features[FEATURE_GLSL3] = true;
	capabilities.features[FEATURE_GLSL4] = true;
	capabilities.features[FEATURE_INSTANCING] = true;
	static_assert(FEATURE_MAX_ENUM == 10, "Graphics::initCapabilities must be updated when adding a new graphics feature!");

	// https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf
	capabilities.limits[LIMIT_POINT_SIZE] = 511;
	capabilities.limits[LIMIT_TEXTURE_SIZE] = 16384; // TODO
	capabilities.limits[LIMIT_TEXTURE_LAYERS] = 2048;
	capabilities.limits[LIMIT_VOLUME_TEXTURE_SIZE] = 2048;
	capabilities.limits[LIMIT_CUBE_TEXTURE_SIZE] = 16384; // TODO
	capabilities.limits[LIMIT_RENDER_TARGETS] = 8; // TODO
	capabilities.limits[LIMIT_TEXTURE_MSAA] = msaa;
	capabilities.limits[LIMIT_ANISOTROPY] = 16.0f;
	static_assert(LIMIT_MAX_ENUM == 8, "Graphics::initCapabilities must be updated when adding a new system limit!");

	for (int i = 0; i < TEXTURE_MAX_ENUM; i++)
		capabilities.textureTypes[i] = true;
}

void Graphics::getAPIStats(int &shaderswitches) const
{
	shaderswitches = 0;
}

} // metal
} // graphics
} // love
