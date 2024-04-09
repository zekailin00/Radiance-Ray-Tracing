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


hitBegin = """
void callHit(int sbtRecordOffset, struct Payload* payload, struct HitData* hitData, struct SceneData* sceneData)
{
    int index = hitData->instanceSBTOffset + sbtRecordOffset;
    switch (index)
    {
"""
hitEnd = """
        default: printf("Error: No hit shader found.");
    }
}
"""

missBegin = """
void callMiss(int missIndex, struct Payload* payload, struct SceneData* sceneData)
{
    switch (missIndex)
    {
"""
missEnd = """
        default: printf("Error: No miss shader found.");
    }
}
"""

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
    
        if data[i]["closestHit"]:
            hit = "\t\tcase " + str(i) + ":" +  data[i]["closestHit"] + "(payload, hitData, sceneData);break;\n"
            hitBranch = hitBranch + hit
        if data[i]["miss"]:
            miss = "\t\tcase " + str(i) +  ":" + data[i]["miss"] + "(payload, sceneData);break;\n"
            missBranch = missBranch + miss

    hitBranch  = hitBegin  + hitBranch  + hitEnd  + '\n'
    missBranch = missBegin + missBranch + missEnd + '\n'

    print("\nGenerated hit branches:")
    print(hitBranch)
    print("Generated miss branches:")
    print(missBranch)

    with open(shader_path, 'r') as file:
        original_content = file.read()

    # Step 2: Combine the original content with the additional string
    combined_content = original_content + hitBranch + missBranch

    # Step 3: Write the combined content to a new file
    with open("./tmp.cl", 'w') as file:
        file.write(combined_content)

    print("The combined content has been successfully written to the new file.")