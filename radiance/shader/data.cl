
struct AccelStructTop // 1 block
{
    unsigned int type;
    unsigned int nodeByteOffset;
    unsigned int instByteOffset;
    unsigned int totalBufferSize;
};

struct AccelStructBottom // 1 block
{
    unsigned int type;
    unsigned int nodeByteOffset;
    unsigned int faceByteOffset;
    unsigned int vertexOffset;
};

struct AccelStruct// 1 block
{
    unsigned int type;
    unsigned int nodeByteOffset;

    union {
        struct {
            unsigned int instByteOffset;
            unsigned int totalBufferSize;
        } top;

        struct {
            unsigned int faceByteOffset;
            unsigned int vertexOffset;
        } bot;
    } u;
};

struct BVHNode // 3 blocks
{
   	float4 _bottom;
	float4 _top;

	union {
		// inner node - stores indexes to children
		struct {
			unsigned int _idxLeft;
			unsigned int _idxRight;
            unsigned int _2, _3; // alignment
		} inner;

		// leaf node: stores face count and references
		struct {
			unsigned int _count; // Top-most bit set, leafnode if set, innernode otherwise
			unsigned int _startIndexList;
            unsigned int _type;
            unsigned int _3; // alignment
		} leaf;
	} node;
};

struct Triangle // 1 block
{
	unsigned int idx0;
	unsigned int idx1;
	unsigned int idx2;
    unsigned int primID;
};

struct Instance // 5 blocks
{
	float4 r0, r1, r2, r3;
    unsigned int SBTOffset, instanceID, customInstanceID, instanceOffset;
};

struct RayTraceProperties
{
    unsigned int totalSamples;
    unsigned int batchSize;
    unsigned int depth;
    unsigned int debug;
};

typedef float4 Vertex; // 1 block

#define TYPE_INST 1
#define TYPE_TRIG 2

#define TYPE_TOP_AS 1
#define TYPE_BOT_AS 2


#define TO_BVH_NODE(accelStruct) (struct BVHNode*)(((char*)accelStruct) + accelStruct->nodeByteOffset)
#define TO_VERTEX(accelStruct)   (Vertex*)(((char*)accelStruct) + accelStruct->u.bot.vertexOffset)
#define TO_FACE(accelStruct)     (struct Triangle*)(((char*)accelStruct) + accelStruct->u.bot.faceByteOffset)
#define TO_INST(accelStruct)     (struct Instance*)(((char*)accelStruct) + accelStruct->u.top.instByteOffset)
#define TO_BOT_AS(topAS, inst)   (struct AccelStruct*)(((char*)topAS) + inst->instanceOffset)

#define IS_LEAF(BVHNode)         (BVHNode->node.leaf._count & 0x80000000)
#define GET_COUNT(BVHNode)       (BVHNode->node.leaf._count & 0x7fffffff)

void printAccelStructTop(struct AccelStruct* in)
{
    printf("AccelStructTop:\n");
    printf("\t type: %u\n", in->type);
    printf("\t nodeByteOffset: %u\n", in->nodeByteOffset);
    printf("\t instByteOffset: %u\n", in->u.top.instByteOffset);
    printf("\t totalBufferSize: %u\n", in->u.top.totalBufferSize);
}

void printAccelStructBottom(struct AccelStruct* in)
{
    printf(
        "AccelStructBottom:\n"
        "\t type: %u\n"
        "\t nodeByteOffset: %u\n"
        "\t faceByteOffset: %u\n"
        "\t vertexOffset: %u\n",
        in->type, in->nodeByteOffset, in->u.bot.faceByteOffset, in->u.bot.vertexOffset);
}

void printBVHNode(struct BVHNode* in)
{
    if (IS_LEAF(in))
    {
        printf("BVHNode:\n"
            // "\t _bottom: <%f, %f, %f>\n"
            // "\t _top: <%f, %f, %f>\n"
            // "\t isLeaf: %u\n"
            "\t _count: %u\n"
            "\t _startIndexList: %u\n"
            "\t _type: %u\n",
            // in->_bottom.x, in->_bottom.y, in->_bottom.z,
            // in->_top.x, in->_top.y, in->_top.z,
            // IS_LEAF(in),
            GET_COUNT(in),
            in->node.leaf._startIndexList, in->node.leaf._type
            );
    }
    else
    {
        // printf("BVHNode:\n"
            // "\t _bottom: <%f, %f, %f>\n"
            // "\t _top: <%f, %f, %f>\n"
            // "\t isLeaf: %d\n"
            // "\t _idxLeft: %u\n"
            // "\t _idxRight: %u\n",
            // in->_bottom.x, in->_bottom.y, in->_bottom.z,
            // in->_top.x, in->_top.y, in->_top.z,
            // IS_LEAF(in),
            // in->node.inner._idxLeft, in->node.inner._idxRight
            // );
    }
}

void printTriangle(struct Triangle* in)
{
    printf("Triangle:\n"
        "\t Indices: <%u, %u, %u>\n"
        "\t primitive ID: %u\n",
        in->idx0, in->idx1, in->idx2, in->primID);
}

void printInstance(struct Instance* in)
{
    printf(
        "Instance:\n"
        // "\t r0: <%f, %f, %f, %f>\n"
        // "\t r1: <%f, %f, %f, %f>\n"
        // "\t r2: <%f, %f, %f, %f>\n"
        // "\t r3: <%f, %f, %f, %f>\n"
        "\t SBTOffset: %u\n"
        "\t instanceID: %u\n"
        "\t customInstanceID: %u\n"
        "\t instanceOffset: %u\n",
        // in->r0.x, in->r0.y, in->r0.z, in->r0.w,
        // in->r1.x, in->r1.y, in->r1.z, in->r1.w,
        // in->r2.x, in->r2.y, in->r2.z, in->r2.w,
        // in->r3.x, in->r3.y, in->r3.z, in->r3.w,
        in->SBTOffset, in->instanceID,
        in->customInstanceID, in->instanceOffset);
}

void printVertex(Vertex* in)
{
    printf("Vertex:\n"
        "\t vert: <%f, %f, %f, %f>\n",
        in->x, in->y, in->z, in->w);
}

void printBotASFromInstance(struct AccelStruct* topLevel, struct Instance* inst)
{
    struct AccelStruct* botAS = TO_BOT_AS(topLevel, inst);
    struct BVHNode* node;
    struct Triangle* triangle;
    Vertex* vertex;

    // printAccelStructBottom(botAS);

    node = TO_BVH_NODE(botAS);
    printBVHNode(node);
    // node++;
    // printBVHNode(node);

    // triangle = TO_FACE(botAS);
    // printTriangle(triangle);
    // triangle++;
    // printTriangle(triangle);

    // vertex = TO_VERTEX(botAS);
    // printVertex(vertex);
    // vertex++;
    // printVertex(vertex);
}

void printTopAS(struct AccelStruct* topLevel)
{
    struct BVHNode* node;
    struct Instance* instance;

    printAccelStructTop(topLevel);

    node = TO_BVH_NODE(topLevel);
    printBVHNode(node);

    instance = TO_INST(topLevel);
    printInstance(instance);
    printBotASFromInstance(topLevel, instance);

    instance++;
    printInstance(instance);
    printBotASFromInstance(topLevel, instance);
}

/*

16-byte block
+--------+
|        | 
+--------+


Top level layout:
+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+
| ASTopH |@        BVH Node         |         BVH Node         |         BVH Node         |
+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+
|@                 Instance                  |                  Instance                  |
+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+


Bottom level layout:
+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+
| ASBotH |@        BVH Node         |         BVH Node         |         BVH Node         |
+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+
|@ Trig  |  Trig  |  Trig  |  Trig  |  Trig  |  Trig  |@ Vert  |  Vert  |  Vert  |  Vert  |
+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+


Example:
+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+
| ASTopH |@        BVH Node         |         BVH Node         |         BVH Node         |
+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+
|@                 Instance                  |                  Instance                  |
+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+
|                  Instance                  |                  Instance                  |
+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+
| ASBotH |@        BVH Node         |         BVH Node         |         BVH Node         |
+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+
|@ Trig  |  Trig  |  Trig  |@ Vert  |  Vert   | Vert  | ASBotH |@        BVH Node         |
+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+
|         BVH Node         |         BVH Node         |         BVH Node         |@ Trig  |
+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+
|@ Trig  |  Trig  |  Trig  |  Trig  |  Trig  |  Trig  |@ Vert  |  Vert  |  Vert  |  Vert  |
+--------+--------+--------+--------+--------+--------+--------+--------+--------+--------+

*/