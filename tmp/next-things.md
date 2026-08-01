### 1. Inter-Chunk Face Culling (Culling de Fronteira)

O seu *Greedy Meshing* atual está excelente para limpar a geometria *interna* do chunk. Porém, se você analisar a sua função `chunk_get_block` atual, quando a busca passa do limite espacial do chunk (`x < 0` ou `x >= CHUNK_SIZE`), ela automaticamente retorna `0` (vazio).

* **O problema:** Isso faz com que o algoritmo acredite que não há nada além da fronteira, forçando a engine a gerar uma parede sólida de polígonos em volta de **absolutamente todos os chunks**. Se você tiver dois chunks sólidos encostados, as faces onde eles se tocam estarão sendo renderizadas à toa.
* **A solução:** O seu *meshing* precisará de acesso de leitura aos chunks vizinhos para saber se a fronteira está bloqueada por um bloco do outro chunk, permitindo apagar essa geometria invisível.

### 2. LOD (Level of Detail) Volumétrico

Com blocos 10 vezes menores, renderizar os detalhes milimétricos de uma montanha a 300 metros de distância de você vai fritar a GPU e não fará diferença visual (os blocos serão menores que um pixel na tela).

* **A solução:** Você precisará criar uma etapa no *Greedy Meshing* que, dependendo da distância do chunk até a câmera, agrupa os blocos. Um chunk distante fundiria dados de $2 \times 2 \times 2$ micro-voxels em apenas 1 vértice maior, reduzindo o custo de renderização em 8x progressivamente à medida que se afasta do jogador.

### 3. Compressão de Memória na CPU (RLE ou Octrees)

No Minecraft clássico, um array chapado (1D) para guardar blocos funciona bem. Com micro-voxels, a memória alocada vai explodir.

* **A solução:** Você precisará parar de guardar os blocos vazios (ar). Em vez de um array fixo de memória, a indústria costuma usar **Octrees** (árvores de divisão espacial) ou **Run-Length Encoding (RLE)**. O RLE guarda apenas instruções do tipo "temos 5.000 blocos de ar em sequência", em vez de declarar 5.000 inteiros `0` na memória.

### 4. Occlusion Culling

Você já implementou o *Frustum Culling*, o que impede a renderização do que está nas costas da câmera. Porém, a câmera ainda tentará desenhar os chunks que estão na sua frente, mas completamente escondidos atrás de uma montanha ou parede sólida.

* **A solução:** Para jogos de mundo aberto com muita profundidade de blocos, técnicas como *Hardware Occlusion Queries* ou um teste de profundidade na CPU ajudam a descartar chunks que já estão tapados por outra geometria mais próxima da tela.
