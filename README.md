XPM FIFO Macro Example:

This is an XPM FIFO used as a simple axis-stream interface. You can modify the width of the data vector and any other metadata you want to append at the end. 

By default, this FIFO appends the metadata at the end of the word (e.g. tlast) and gets FIFO'd through and attached to the tlast of the output stream.

Optionally, you can enable CDC. You can also adjust pipeline stages. The CDC, common clock, pipeline, and metadata sections were tested and verified in MATLAB and on hardware. the width exponent and the depth must sum to 15 (e.g. WIDTH_EXP = 3 -> data width of 8, 15 - 3 -> depth of exponent 12
