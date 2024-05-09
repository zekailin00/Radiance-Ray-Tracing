import json

# Function to load and read a JSON file
def read_json_file(file_path):
    try:
        with open(file_path, 'r') as file:
            # Load file content into a Python dictionary
            data = json.load(file)
            return data
    except FileNotFoundError:
        print(f"File {file_path} not found.")
    except json.JSONDecodeError:
        print(f"Error decoding JSON from file {file_path}.")
    except Exception as e:
        print(f"An error occurred: {e}")


anyHitBegin = """
void callAnyHit(bool* cont, int sbtRecordOffset, struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData TEXTURE_TYPE)
{
    int index = hitData->instanceSBTOffset + sbtRecordOffset;
    switch (index)
    {
"""
anyHitEnd = """
    }
}
"""


hitBegin = """
void callHit(int sbtRecordOffset, struct Payload* payload, struct HitData* hitData,
    struct SceneData* sceneData TEXTURE_TYPE)
{
    int index = hitData->instanceSBTOffset + sbtRecordOffset;
    switch (index)
    {
"""
hitEnd = """
    }
}
"""

missBegin = """
void callMiss(int missIndex, struct Payload* payload,
    struct SceneData* sceneData TEXTURE_TYPE)
{
    switch (missIndex)
    {
"""
missEnd = """
    }
}
"""

anyHitBranch = ""
hitBranch = ""
missBranch = ""

if __name__ == "__main__":
    # Specify your JSON file path here
    json_path = "/home/zekailin00/Desktop/ray-tracing/framework/samples/sbt.json"
    shader_path = "/home/zekailin00/Desktop/ray-tracing/framework/samples/shader.cl"

    data = read_json_file(json_path)

    for i in range(len(data)):
        print("1. raygen :", data[i]["raygen"],
              "  2. closestHit: ",  data[i]["closestHit"], 
              "  3. anyHit: ", data[i]["anyHit"],
              "  4. miss: ",  data[i]["miss"])
        
        if data[i]["anyHit"]:
            anyHit = "\t\tcase " + str(i) + ":" +  data[i]["anyHit"] + "(cont, payload, hitData, sceneData TEXTURE_PARAM);break;\n"
            anyHitBranch = anyHitBranch + anyHit
        if data[i]["closestHit"]:
            hit = "\t\tcase " + str(i) + ":" +  data[i]["closestHit"] + "(payload, hitData, sceneData TEXTURE_PARAM);break;\n"
            hitBranch = hitBranch + hit
        if data[i]["miss"]:
            miss = "\t\tcase " + str(i) +  ":" + data[i]["miss"] + "(payload, sceneData TEXTURE_PARAM);break;\n"
            missBranch = missBranch + miss

    anyHitBranch = anyHitBegin + anyHitBranch + anyHitEnd + '\n'
    hitBranch    = hitBegin  + hitBranch  + hitEnd  + '\n'
    missBranch   = missBegin + missBranch + missEnd + '\n'

    print("\nGenerated anyHit branches:")
    print(anyHitBranch)
    print("Generated hit branches:")
    print(hitBranch)
    print("Generated miss branches:")
    print(missBranch)

    with open(shader_path, 'r') as file:
        original_content = file.read()

    # Step 2: Combine the original content with the additional string
    combined_content = original_content + anyHitBranch + hitBranch + missBranch

    # Step 3: Write the combined content to a new file
    with open("./tmp.cl", 'w') as file:
        file.write(combined_content)

    print("The combined content has been successfully written to the new file.")