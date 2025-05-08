#!/bin/bash
shopt -s globstar

CUT=$(sed '/"Files"/,$d' $1)
echo "$CUT" > $2
printf '  "Files"\n  {\n' >> $2
printf '    "Plugin"      "Path_SM/%s"\n' plugins/**/*.* >> $2
printf '    "Plugin"      "Path_SM/%s"\n' translations/**/*.* >> $2
printf '    "Source"      "Path_SM/%s"\n' scripting/**/*.* >> $2
printf '  }' >> $2
printf '}' >> $2