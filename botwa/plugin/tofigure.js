const axios = require("axios");
const FormData = require("form-data");

async function convert(buffers, prompt) {
    const buffer = buffers[0];
    const form = new FormData();
    form.append("image", buffer, "image.jpg");
    form.append("prompt", prompt);

    const response = await axios.post("https://api.xyro.site/ai/notegpt/edit", form, {
        headers: form.getHeaders(),
        timeout: 120000
    });

    if (!response.data?.status || !response.data.data?.results?.length) {
        throw new Error("Gagal mendapatkan hasil dari API XYRO");
    }

    const resultUrl = response.data.data.results[0].url;
    const imgBuffer = await axios.get(resultUrl, { responseType: "arraybuffer" })
        .then(res => Buffer.from(res.data, "binary"));

    return imgBuffer;
}

let handler = async (m, { client, command, prefix, reply }) => {
    let q = m.quoted ? m.quoted : m;
    let mime = (q.msg || q).mimetype || '';

    try {
        if (!/image/.test(mime)) {
            return reply(`⚠️ Harap balas gambar yang ingin Anda ubah menjadi figurine.\nContoh: Balas gambar dengan caption *${prefix}${command}*`);
        }

        await client.sendMessage(m.chat, { react: { text: '⏳', key: m.key } });

        const mediaBuffer = await q.download();
        const prompt = 'a commercial 1/7 scale figurine of the character in the picture was created, depicting a realistic style and a realistic environment. The figurine is placed on a computer desk with a round transparent acrylic base. There is no text on the base. The computer screen shows the Zbrush modeling process of the figurine. Next to the computer screen is a BANDAI-style toy box with the original painting printed on it.';

        const resultBuffer = await convert([mediaBuffer], prompt);

        await client.sendMessage(m.chat, {
            image: resultBuffer,
            caption: '✅ Figurine Anda berhasil dibuat dengan AI XYRO!'
        }, { quoted: m });
        
        await client.sendMessage(m.chat, { react: { text: '✅', key: m.key } });

    } catch (error) {
        console.error("Error in 'tofigure' command:", error);
        reply(`❌ Terjadi kesalahan saat membuat figurine: ${error.message}`);
        await client.sendMessage(m.chat, { react: { text: '❌', key: m.key } });
    }
};

handler.help = ['tofigure'];
handler.tags = ['ai', 'maker'];
handler.command = ['tofigure'];
handler.limit = 5;

module.exports = handler;
