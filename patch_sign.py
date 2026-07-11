import os

pw = os.environ.get("KEYPW", "")
if not pw:
    print("!! KEYPW 환경변수가 비어있음. KEYPW='비번' python3 patch_sign.py 로 실행하세요.")
    raise SystemExit(1)

ks_path = os.path.expanduser("~/upload-keystore.jks")
if not os.path.exists(ks_path):
    print("!! 키스토어가 ~/upload-keystore.jks 에 없음:", ks_path)
    raise SystemExit(1)

# 1) key.properties (gitignore 됨)
with open("android/key.properties", "w") as f:
    f.write(
        "storePassword=%s\n"
        "keyPassword=%s\n"
        "keyAlias=upload\n"
        "storeFile=%s\n" % (pw, pw, ks_path)
    )

# 2) .gitignore 에 비밀 항목 추가
gi = "android/.gitignore"
existing = open(gi).read() if os.path.exists(gi) else ""
add = ""
for line in ["key.properties", "*.jks", "*.keystore"]:
    if line not in existing:
        add += line + "\n"
if add:
    with open(gi, "a") as f:
        f.write("\n# release signing secrets\n" + add)

# 3) build.gradle.kts 서명 설정
p = "android/app/build.gradle.kts"
s = open(p).read()
if "java.util.Properties" not in s:
    s = "import java.util.Properties\nimport java.io.FileInputStream\n\n" + s
if "val keystoreProperties" not in s:
    valblock = (
        'val keystoreProperties = Properties()\n'
        'val keystorePropertiesFile = rootProject.file("key.properties")\n'
        'if (keystorePropertiesFile.exists()) {\n'
        '    keystoreProperties.load(FileInputStream(keystorePropertiesFile))\n'
        '}\n\n'
    )
    s = s.replace("android {", valblock + "android {", 1)
if "signingConfigs {" not in s:
    sc = (
        '\n    signingConfigs {\n'
        '        create("release") {\n'
        '            keyAlias = keystoreProperties["keyAlias"] as String?\n'
        '            keyPassword = keystoreProperties["keyPassword"] as String?\n'
        '            storeFile = keystoreProperties["storeFile"]?.let { file(it) }\n'
        '            storePassword = keystoreProperties["storePassword"] as String?\n'
        '        }\n'
        '    }\n'
    )
    s = s.replace("android {\n", "android {\n" + sc, 1)
s = s.replace('signingConfigs.getByName("debug")', 'signingConfigs.getByName("release")')
open(p, "w").write(s)

print("=== 서명 설정 완료 ===")
print("key.properties (비번 가림):")
print(open("android/key.properties").read().replace(pw, "********"))
print("build.gradle.kts 에 signingConfigs 들어감:", "signingConfigs {" in open(p).read())
print("release가 release키 사용:", 'getByName("release")' in open(p).read())
