#!/bin/bash
V_DIR="./examples/1_3examples/"
V_FAILED=()
# run validation for all example files
for i in $(find "$V_DIR" -maxdepth 3 -iname '*.mzid'); do
  echo -e "################################################################################"
  echo -e "# Starting basic validation of $i"
  xmllint --noout --schema ./schema/mzIdentML1.3.0.xsd $i
  if [ $? -ne 0 ];
  then
    echo -e "# Validation of file $i failed! Please check console output for errors!"
    V_FAILED+=($i)
  else
    echo -e "# Validation of file $i was successful. Please check console output for hints for improvment!"
  fi
  echo -e "################################################################################"
done

if [ ${#V_FAILED[@]} -ne 0 ]; then
  echo -e "################################################################################"
  echo -e "# Validation failed for ${#V_FAILED[@]} files! Please check the following files:"
  for i in "${V_FAILED[@]}"
  do
   echo "# $i"
  done
  echo -e "################################################################################"
  exit 3
else
  echo -e "################################################################################"
  echo -e "# Validation of all files successful!"
  echo -e "################################################################################"
  exit 0
fi
