#version 450

#extension GL_EXT_shader_16bit_storage: require
#extension GL_EXT_shader_8bit_storage: require

#extension GL_GOOGLE_include_directive: require

#include "mesh.h"

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(push_constant) uniform block
{
	DrawCullData cullData;
};

layout(binding = 0) readonly buffer Draws
{
	MeshDraw draws[];
};

layout(binding = 1) readonly buffer Meshes
{
	Mesh meshes[];
};

layout(binding = 2) writeonly buffer DrawCommands
{
	MeshDrawCommand drawCommands[];
};

layout(binding = 3) buffer DrawCommandCount
{
	uint drawCommandCount;
};

void main()
{
	uint di = gl_GlobalInvocationID.x;

	if (di >= cullData.drawCount)
		return;

	uint meshIndex = draws[di].meshIndex;
	Mesh mesh = meshes[meshIndex];

	vec3 center = rotateQuat(mesh.center, draws[di].orientation) * draws[di].scale + draws[di].position;
	float radius = mesh.radius * draws[di].scale;

	bool visible = true;
	// the left/top/right/bottom plane culling utilizes frustum symmetry to cull against two planes at the same time
	visible = visible && center.z * cullData.frustum[1] - abs(center.x) * cullData.frustum[0] > -radius;
	visible = visible && center.z * cullData.frustum[3] - abs(center.y) * cullData.frustum[2] > -radius;
	// the near/far plane culling uses camera space Z directly
	visible = visible && center.z + radius > cullData.znear && center.z - radius < cullData.zfar;

	visible = visible || cullData.cullingEnabled == 0;

	// uint dci = atomicAdd(drawCommandCount, 1);

	// lod distance i = base * pow(step, i)
	// i = log2(distance / base) / log2(step)
	float lodIndexF = log2(length(center) / cullData.lodBase) / log2(cullData.lodStep);
	uint lodIndex = min(uint(max(lodIndexF + 1, 0)), mesh.lodCount - 1);

	lodIndex = cullData.lodEnabled == 1 ? lodIndex : 0;

	MeshLod lod = meshes[meshIndex].lods[lodIndex];

	uint instanceCount = 1;

	drawCommands[di].drawId = di;
	drawCommands[di].indexCount = lod.indexCount;
	drawCommands[di].instanceCount = visible ? 1 : 0;
	drawCommands[di].firstIndex = lod.indexOffset;
	drawCommands[di].vertexOffset = mesh.vertexOffset;
	drawCommands[di].firstInstance = di;
	drawCommands[di].taskCount = (lod.meshletCount + 31) / 32;
	drawCommands[di].firstTask = lod.meshletOffset / 32;

}
