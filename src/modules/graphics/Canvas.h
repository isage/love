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

#pragma once

#include "image/Image.h"
#include "image/ImageData.h"
#include "Texture.h"
#include "common/Optional.h"
#include "common/StringMap.h"

namespace love
{
namespace graphics
{

class Graphics;

class Canvas : public Texture
{
public:

	static love::Type type;

	enum SettingType
	{
		SETTING_WIDTH,
		SETTING_HEIGHT,
		SETTING_LAYERS,
		SETTING_MIPMAPS,
		SETTING_FORMAT,
		SETTING_TYPE,
		SETTING_DPI_SCALE,
		SETTING_MSAA,
		SETTING_READABLE,
		SETTING_MAX_ENUM
	};

	struct Settings
	{
		int width  = 1;
		int height = 1;
		int layers = 1; // depth for 3D textures
		MipmapsMode mipmaps = MIPMAPS_NONE;
		PixelFormat format = PIXELFORMAT_NORMAL;
		TextureType type = TEXTURE_2D;
		float dpiScale = 1.0f;
		int msaa = 0;
		OptionalBool readable;
	};

	Canvas(const Settings &settings);
	virtual ~Canvas();

	MipmapsMode getMipmapsMode() const;

	virtual love::image::ImageData *newImageData(love::image::Image *module, int slice, int mipmap, const Rect &rect);

	static bool getConstant(const char *in, SettingType &out);
	static bool getConstant(SettingType in, const char *&out);
	static const char *getConstant(SettingType in);
	static std::vector<std::string> getConstants(SettingType);

protected:

	Settings settings;

private:

	static StringMap<MipmapsMode, MIPMAPS_MAX_ENUM>::Entry mipmapEntries[];
	static StringMap<MipmapsMode, MIPMAPS_MAX_ENUM> mipmapModes;

	static StringMap<SettingType, SETTING_MAX_ENUM>::Entry settingTypeEntries[];
	static StringMap<SettingType, SETTING_MAX_ENUM> settingTypes;
	
}; // Canvas

} // graphics
} // love
